#!/bin/bash
set -euo pipefail

PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="us-central1"
ZONE_A="us-central1-a"
ZONE_B="us-central1-b"
BUCKET_NAME="cs528-pagerank-eddielu-1790373540"
SA_NAME="hw8-web-sa"
SA_EMAIL="$SA_NAME@$PROJECT.iam.gserviceaccount.com"
MACHINE="e2-micro"
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"

echo "Project: $PROJECT"
gcloud config set project "$PROJECT" >/dev/null
gcloud services enable compute.googleapis.com logging.googleapis.com

if ! gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" --display-name="HW8 web server"
  sleep 15
fi
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET_NAME" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectViewer" >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/logging.logWriter" \
  --condition=None >/dev/null

gcloud compute firewall-rules create hw8-allow-http \
  --network=default --direction=INGRESS --action=ALLOW --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 --target-tags=hw8-web
gcloud compute firewall-rules create hw8-allow-service2 \
  --network=default --direction=INGRESS --action=ALLOW --rules=tcp:8080 \
  --source-tags=hw8-web --target-tags=hw8-service2

gcloud compute instances create hw8-service2 \
  --zone="$ZONE_A" --machine-type="$MACHINE" \
  --image-family="$IMAGE_FAMILY" --image-project="$IMAGE_PROJECT" \
  --tags=hw8-service2 \
  --metadata-from-file=startup-script=startup-service2.sh

SERVICE2_IP=$(gcloud compute instances describe hw8-service2 --zone="$ZONE_A" \
  --format='value(networkInterfaces[0].networkIP)')
SERVICE2_URL="http://$SERVICE2_IP:8080/banned-alert"
echo "Service 2 URL: $SERVICE2_URL"

for Z in a b; do
  ZONE="us-central1-$Z"
  gcloud compute instances create "hw8-web-$Z" \
    --zone="$ZONE" --machine-type="$MACHINE" \
    --image-family="$IMAGE_FAMILY" --image-project="$IMAGE_PROJECT" \
    --tags=hw8-web \
    --service-account="$SA_EMAIL" --scopes=cloud-platform \
    --metadata="service2-url=$SERVICE2_URL,bucket-name=$BUCKET_NAME" \
    --metadata-from-file=startup-script=startup-web.sh
  gcloud compute instance-groups unmanaged create "hw8-ig-$Z" --zone="$ZONE"
  gcloud compute instance-groups unmanaged add-instances "hw8-ig-$Z" \
    --zone="$ZONE" --instances="hw8-web-$Z"
done

gcloud compute health-checks create http hw8-hc \
  --region="$REGION" --port=80 --request-path=/health \
  --check-interval=2s --timeout=2s \
  --unhealthy-threshold=2 --healthy-threshold=2

gcloud compute backend-services create hw8-backend \
  --region="$REGION" --load-balancing-scheme=EXTERNAL --protocol=TCP \
  --health-checks=hw8-hc --health-checks-region="$REGION"

gcloud compute backend-services add-backend hw8-backend \
  --region="$REGION" --instance-group=hw8-ig-a --instance-group-zone="$ZONE_A"
gcloud compute backend-services add-backend hw8-backend \
  --region="$REGION" --instance-group=hw8-ig-b --instance-group-zone="$ZONE_B"

gcloud compute addresses create hw8-lb-ip --region="$REGION"

gcloud compute forwarding-rules create hw8-fr \
  --region="$REGION" --load-balancing-scheme=EXTERNAL \
  --ports=80 --address=hw8-lb-ip --backend-service=hw8-backend

LB_IP=$(gcloud compute addresses describe hw8-lb-ip --region="$REGION" --format='value(address)')

echo "Waiting for both backends to become HEALTHY (VMs need a few minutes to install)..."
for _ in $(seq 1 60); do
  HEALTHY=$(gcloud compute backend-services get-health hw8-backend --region="$REGION" \
    --format='value(status.healthStatus[].healthState)' | tr ';' '\n' | grep -c '^HEALTHY$' || true)
  echo "  healthy backends: $HEALTHY/2"
  [ "$HEALTHY" -ge 2 ] && break
  sleep 10
done

gcloud compute backend-services get-health hw8-backend --region="$REGION"
echo
echo "Load balancer IP: $LB_IP"
echo "Try: curl -si http://$LB_IP/files/0.html | head -8"
