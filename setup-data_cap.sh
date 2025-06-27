# Setup Instructions for Logstash Daily Limits

# 1. Install the cleanup script
sudo cp cleanup_overflow.sh /opt/logstash/bin/
sudo chmod +x /opt/logstash/bin/cleanup_overflow.sh
sudo chown logstash:logstash /opt/logstash/bin/cleanup_overflow.sh

# 2. Create environment file (update values as needed)
sudo cp .env /opt/logstash/.env
sudo chown logstash:logstash /opt/logstash/.env
sudo chmod 600 /opt/logstash/.env

# 3. Configure Logstash to load environment variables
# Add to /etc/systemd/system/logstash.service or your Logstash startup:
# EnvironmentFile=/opt/logstash/.env

# Or load via shell profile:
echo 'source /opt/logstash/.env' | sudo tee -a /home/logstash/.bashrc

# 4. Add to logstash user's crontab
sudo -u logstash crontab -e
# Add this line:
# 0 2 * * * /bin/bash -c 'source /opt/logstash/.env && /opt/logstash/bin/cleanup_overflow.sh >> /var/log/logstash/cleanup.log 2>&1'

# 5. Alternative: Create systemd timer with environment file
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
sudo systemctl daemon-reload
sudo systemctl enable logstash-cleanup.timer
sudo systemctl start logstash-cleanup.timer

# 6. Start Logstash with environment variables
# Method 1: Systemd service with EnvironmentFile
sudo systemctl edit logstash
# Add:
# [Service]
# EnvironmentFile=/opt/logstash/.env

# Method 2: Manual start with env file
sudo -u logstash bash -c 'source /opt/logstash/.env && /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/logstash.conf'

# 7. Create required directories
sudo mkdir -p /opt/logstash/data /opt/logstash/overflow /var/log/logstash
sudo chown -R logstash:logstash /opt/logstash/ /var/log/logstash

# 8. Test the script manually
sudo -u logstash bash -c 'source /opt/logstash/.env && /opt/logstash/bin/cleanup_overflow.sh'

# 9. Check timer status
sudo systemctl status logstash-cleanup.timer
sudo systemctl list-timers logstash-cleanup.timer