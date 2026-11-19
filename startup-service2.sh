#!/bin/bash
set -e

REPO_URL="https://github.com/adefifp/cs528-hw8.git"
APP_DIR="/opt/hw8"

apt-get update -y
apt-get install -y git python3-venv

if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull
else
  git clone "$REPO_URL" "$APP_DIR"
fi

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install flask

cat > /etc/systemd/system/hw8-service2.service <<EOF
[Unit]
Description=CS528 HW8 forbidden-request service
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/service2.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw8-service2
systemctl restart hw8-service2
