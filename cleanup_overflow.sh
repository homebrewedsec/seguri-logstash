#!/bin/bash
# /opt/logstash/bin/cleanup_overflow.sh
# Manages 7-day retention of overflow files with alerts

set -euo pipefail

OVERFLOW_DIR="/opt/logstash/overflow"
LOGSTASH_HOST="${LOGSTASH_HOST:-$(hostname)}"
ELASTIC_HOSTS="${ELASTIC_HOSTS}"
ELASTIC_API_KEY="${ELASTIC_API_KEY}"

# Calculate dates
PURGE_DATE=$(date -d '7 days ago' '+%Y-%m-%d')
ALERT_DATE=$(date -d '6 days ago' '+%Y-%m-%d')

# Function to send alert to Elasticsearch
send_alert() {
    local alert_type="$1"
    local files="$2"
    local file_count="$3"
    local total_size="$4"
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    local alert_json=$(cat <<EOF
{
    "@timestamp": "$timestamp",
    "message": "Logstash overflow file $alert_type",
    "service.name": "logstash",
    "service.type": "ingestion",
    "host.name": "$LOGSTASH_HOST",
    "log.level": "INFO",
    "event.kind": "alert",
    "event.category": ["file"],
    "event.type": ["$alert_type"],
    "event.dataset": "logstash.cleanup",
    "logstash.cleanup.type": "$alert_type",
    "logstash.cleanup.file_count": $file_count,
    "logstash.cleanup.total_size_bytes": $total_size,
    "logstash.cleanup.target_date": "$([[ $alert_type == "pre_purge" ]] && echo $PURGE_DATE || echo $PURGE_DATE)",
    "logstash.cleanup.files": "$files"
}
EOF
)
    
    # Extract host from ELASTIC_HOSTS array format and send to Elasticsearch
    ELASTIC_HOST=$(echo $ELASTIC_HOSTS | sed 's/.*"\(https:\/\/[^"]*\)".*/\1/')
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: ApiKey $ELASTIC_API_KEY" \
        "$ELASTIC_HOST/logstash-alerts-$(date '+%Y.%m.%d')/_doc" \
        -d "$alert_json" > /dev/null
}

# Check for files to be purged tomorrow (6 days old)
check_pre_purge() {
    local files_to_alert=$(find "$OVERFLOW_DIR" -name "replay-$ALERT_DATE-*.jsonl" -type f 2>/dev/null || true)
    
    if [[ -n "$files_to_alert" ]]; then
        local file_count=$(echo "$files_to_alert" | wc -l)
        local total_size=$(echo "$files_to_alert" | xargs ls -l | awk '{sum += $5} END {print sum+0}')
        local file_list=$(echo "$files_to_alert" | tr '\n' ',' | sed 's/,$//')
        
        send_alert "pre_purge" "$file_list" "$file_count" "$total_size"
        echo "Pre-purge alert sent for $file_count files from $ALERT_DATE"
    fi
}

# Purge files older than 7 days
purge_old_files() {
    local files_to_purge=$(find "$OVERFLOW_DIR" -name "replay-$PURGE_DATE-*.jsonl" -type f 2>/dev/null || true)
    
    if [[ -n "$files_to_purge" ]]; then
        local file_count=$(echo "$files_to_purge" | wc -l)
        local total_size=$(echo "$files_to_purge" | xargs ls -l | awk '{sum += $5} END {print sum+0}')
        local file_list=$(echo "$files_to_purge" | tr '\n' ',' | sed 's/,$//')
        
        # Remove files
        echo "$files_to_purge" | xargs rm -f
        
        # Send post-purge alert
        send_alert "post_purge" "$file_list" "$file_count" "$total_size"
        echo "Purged $file_count files from $PURGE_DATE, total size: $total_size bytes"
    else
        echo "No files to purge for $PURGE_DATE"
    fi
}

# Main execution
main() {
    if [[ ! -d "$OVERFLOW_DIR" ]]; then
        echo "Overflow directory does not exist: $OVERFLOW_DIR"
        exit 1
    fi
    
    echo "Starting cleanup process at $(date)"
    
    # Send pre-purge alert for tomorrow's purge
    check_pre_purge
    
    # Purge today's eligible files
    purge_old_files
    
    echo "Cleanup process completed at $(date)"
}

main "$@"