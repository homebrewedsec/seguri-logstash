#!/bin/bash
# setup_logstash.sh - Automated setup for Logstash daily limits

set -euo pipefail

echo "Setting up Logstash Daily Limits configuration..."

# Create required directories
echo "Creating directories..."
sudo mkdir -p /opt/logstash/data /opt/logstash/overflow /opt/logstash/bin /var/log/logstash /etc/logstash/conf.d
sudo chown -R logstash:logstash /opt/logstash/ /var/log/logstash

# Download configuration files
echo "Downloading configuration files..."
sudo curl -o /etc/logstash/conf.d/elastic-agent.conf https://raw.githubusercontent.com/homebrewedsec/seguri-logstash/refs/heads/main/elastic-agent.conf
sudo curl -o /opt/logstash/bin/cleanup_overflow.sh https://raw.githubusercontent.com/homebrewedsec/seguri-logstash/refs/heads/main/cleanup_overflow.sh

# Set permissions
echo "Setting permissions..."
sudo chmod +x /opt/logstash/bin/cleanup_overflow.sh
sudo chown logstash:logstash /etc/logstash/conf.d/elastic-agent.conf /opt/logstash/bin/cleanup_overflow.sh

# Create environment file template
echo "Creating environment file template..."
sudo tee /opt/logstash/.env << 'EOF'
# Logstash Daily Limits Configuration
LOGSTASH_DAILY_LIMIT_GB=10
ORGANIZATION_ID=org-12345
LOGSTASH_LISTEN_IP=0.0.0.0
LOGSTASH_LISTEN_PORT=5044
LOGSTASH_TRACKING_FILE=/opt/logstash/data/daily_usage.json
LOGSTASH_OVERFLOW_DIR=/opt/logstash/overflow
ELASTIC_HOSTS=["https://your-elastic-host:443"]
ELASTIC_API_KEY=your-api-key-here
LOGSTASH_HOST=$(hostname)
EOF
sudo chown logstash:logstash /opt/logstash/.env
sudo chmod 600 /opt/logstash/.env

# Create systemd cleanup service
echo "Creating systemd cleanup service..."
sudo tee /etc/systemd/system/logstash-cleanup.service << 'EOF'
[Unit]
Description=Logstash Overflow Cleanup
After=network.target

[Service]
Type=oneshot
User=logstash
Group=logstash
EnvironmentFile=/opt/logstash/.env
ExecStart=/opt/logstash/bin/cleanup_overflow.sh
StandardOutput=append:/var/log/logstash/cleanup.log
StandardError=append:/var/log/logstash/cleanup.log
EOF

sudo tee /etc/systemd/system/logstash-cleanup.timer << 'EOF'
[Unit]
Description=Run Logstash Cleanup Daily
Requires=logstash-cleanup.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

# Enable systemd timer
echo "Enabling cleanup timer..."
sudo systemctl daemon-reload
sudo systemctl enable logstash-cleanup.timer
sudo systemctl start logstash-cleanup.timer

# Configure Logstash to use environment file
echo "Configuring Logstash service..."
sudo systemctl edit logstash --force --full || true
if ! sudo systemctl cat logstash | grep -q "EnvironmentFile=/opt/logstash/.env"; then
    echo "Adding EnvironmentFile to logstash service..."
    sudo mkdir -p /etc/systemd/system/logstash.service.d
    sudo tee /etc/systemd/system/logstash.service.d/override.conf << 'EOF'
[Service]
EnvironmentFile=/opt/logstash/.env
EOF
    sudo systemctl daemon-reload
fi

echo ""
echo "Setup complete! Next steps:"
echo "1. Edit /opt/logstash/.env with your actual values"
echo "2. Test: sudo -u logstash bash -c 'source /opt/logstash/.env && /opt/logstash/bin/cleanup_overflow.sh'"
echo "3. Restart logstash: sudo systemctl restart logstash"
echo "4. Check cleanup timer: sudo systemctl status logstash-cleanup.timer"