#!/bin/bash
set -e

REPO_URL="https://github.com/adefifp/cs528-hw8.git"
APP_DIR="/opt/hw8"
MD="http://metadata.google.internal/computeMetadata/v1/instance/attributes"

SERVICE_2_URL=$(curl -sf -H "Metadata-Flavor: Google" "$MD/service2-url" || echo "")
BUCKET_NAME=$(curl -sf -H "Metadata-Flavor: Google" "$MD/bucket-name" || echo "")

apt-get update -y
apt-get install -y git python3-venv

if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull
else
  git clone "$REPO_URL" "$APP_DIR"
fi

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"

cat > /etc/systemd/system/hw8-web.service <<EOF
[Unit]
Description=CS528 HW8 web server
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
Environment=SERVICE_2_URL=$SERVICE_2_URL
Environment=BUCKET_NAME=$BUCKET_NAME
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/server.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw8-web
systemctl restart hw8-web
