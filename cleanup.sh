#!/bin/bash

REGION="us-central1"

gcloud compute forwarding-rules delete hw8-fr --region="$REGION" --quiet
gcloud compute addresses delete hw8-lb-ip --region="$REGION" --quiet
gcloud compute backend-services delete hw8-backend --region="$REGION" --quiet
gcloud compute health-checks delete hw8-hc --region="$REGION" --quiet

for Z in a b; do
  gcloud compute instance-groups unmanaged delete "hw8-ig-$Z" --zone="us-central1-$Z" --quiet
  gcloud compute instances delete "hw8-web-$Z" --zone="us-central1-$Z" --quiet
done
gcloud compute instances delete hw8-service2 --zone=us-central1-a --quiet
gcloud compute instances delete hw8-client --zone=us-central1-c --quiet 2>/dev/null

gcloud compute firewall-rules delete hw8-allow-http hw8-allow-service2 --quiet

echo "Cleanup done. The hw8-web-sa service account was kept."
