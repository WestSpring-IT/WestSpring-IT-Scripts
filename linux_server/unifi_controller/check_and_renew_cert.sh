#!/bin/bash
set -euo pipefail

# ==============================================
# Configuration
# ==============================================
DOMAIN="*.westspring-it.co.uk"  # Update this to your domain
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
KEYSTORE_PATH="/usr/lib/unifi/data/keystore"
P12_FILE="$(date '+%Y_%m')_unifi.p12"
PASSWORD="aircontrolenterprise"  # Default Unifi keystore password

LOG_DIR="/home/ubuntu/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y_%m')_ssl_renewal.log"

FORCE_SYNC=false
if [ "${1:-}" == "--force-sync" ]; then
    FORCE_SYNC=true
fi

# ==============================================
# Logging function
# ==============================================
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ==============================================
# Helper: Extract expiry from keystore
# ==============================================
get_keystore_expiry() {
    sudo keytool -exportcert \
        -alias unifi \
        -keystore "$KEYSTORE_PATH/keystore" \
        -storepass $PASSWORD 2>/dev/null |
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 | xargs
}

# ==============================================
# Helper: Calculate days until expiry
# ==============================================
days_until_expiry() {
    local expiry_date="$1"
    local expiry_s
    expiry_s=$(date -u -d "$expiry_date" +%s 2>/dev/null || echo "")
    local now_s
    now_s=$(date -u +%s)
    if [ -z "$expiry_s" ]; then
        echo 9999
    else
        echo $(( (expiry_s - now_s) / 86400 ))
    fi
}

# ==============================================
# Step 1: Get Let's Encrypt certificate expiry
# ==============================================
if [ ! -f "$CERT_PATH/fullchain.pem" ]; then
    log "ERROR: Certificate file not found at $CERT_PATH/fullchain.pem"
    exit 1
fi

EXPIRY_LE=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2 | xargs)
DAYS_LE=$(days_until_expiry "$EXPIRY_LE")
log "Let's Encrypt certificate expiry: $EXPIRY_LE ($DAYS_LE day(s) remaining)."

# ==============================================
# Step 2: Get Unifi keystore certificate expiry
# ==============================================
EXPIRY_UNIFI=""
DAYS_UNIFI=9999
if [ -f "$KEYSTORE_PATH/keystore" ]; then
    EXPIRY_UNIFI=$(get_keystore_expiry || true)
    if [ -n "$EXPIRY_UNIFI" ]; then
        DAYS_UNIFI=$(days_until_expiry "$EXPIRY_UNIFI")
        log "Unifi keystore certificate expiry: $EXPIRY_UNIFI ($DAYS_UNIFI day(s) remaining)."
    else
        log "Could not read expiry date from Unifi keystore."
    fi
else
    log "Unifi keystore not found at $KEYSTORE_PATH/keystore."
fi

# ==============================================
# Step 3: Determine renewal/sync actions
# ==============================================
RENEW=false
APPLY=false

if $FORCE_SYNC; then
    log "🔧 --force-sync flag detected. Forcing Unifi keystore rebuild."
    APPLY=true

elif [ "$DAYS_UNIFI" -le 7 ]; then
    log "Unifi keystore certificate expiring soon (<7 days)."
    if [ "$DAYS_LE" -le 7 ]; then
        log "Let's Encrypt certificate also expiring soon. Renewal required."
        RENEW=true
    else
        log "Let's Encrypt certificate is still valid. Will reapply it to Unifi."
        APPLY=true
    fi
else
    log "Unifi keystore certificate valid for more than 7 days. No immediate action needed."
fi

# ==============================================
# Step 4: Renewal (if required)
# ==============================================
if $RENEW; then
    log "Starting Let's Encrypt renewal..."
    sudo systemctl stop unifi >> "$LOG_FILE" 2>&1 || true
    sudo pkill -f "java.*unifi" || true
    sleep 5
    sudo certbot renew >> "$LOG_FILE" 2>&1

    EXPIRY_LE=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2 | xargs)
    DAYS_LE=$(days_until_expiry "$EXPIRY_LE")
    log "New Let's Encrypt expiry: $EXPIRY_LE ($DAYS_LE day(s) remaining)."
    APPLY=true
fi

# ==============================================
# Step 5: Apply (rebuild Unifi keystore)
# ==============================================
if $APPLY; then
    log "Applying Let's Encrypt certificate to Unifi Controller..."

    sudo systemctl stop unifi >> "$LOG_FILE" 2>&1 || true
    sudo pkill -f "java.*unifi" || true
    sleep 5

    # Backup existing keystore
    if [ -f "$KEYSTORE_PATH/keystore" ]; then
        sudo cp "$KEYSTORE_PATH/keystore" "$KEYSTORE_PATH/keystore.backup.$(date '+%Y%m%d_%H%M%S')" >> "$LOG_FILE" 2>&1
    fi

    # Remove old keystore
    sudo rm -f "$KEYSTORE_PATH/keystore" >> "$LOG_FILE" 2>&1

    # Create PKCS12 file from Let's Encrypt certificates
    sudo openssl pkcs12 -export \
        -inkey "$CERT_PATH/privkey.pem" \
        -in "$CERT_PATH/cert.pem" \
        -certfile "$CERT_PATH/chain.pem" \
        -name unifi \
        -out "$KEYSTORE_PATH/$P12_FILE" \
        -password pass:$PASSWORD >> "$LOG_FILE" 2>&1

    # Import PKCS12 into Java keystore
    sudo keytool -importkeystore \
        -noprompt \
        -deststorepass $PASSWORD \
        -destkeystore "$KEYSTORE_PATH/keystore" \
        -srckeystore "$KEYSTORE_PATH/$P12_FILE" \
        -srcstoretype PKCS12 \
        -srcstorepass $PASSWORD \
        -alias unifi >> "$LOG_FILE" 2>&1

    # Set proper permissions
    sudo chown unifi:unifi "$KEYSTORE_PATH/keystore" >> "$LOG_FILE" 2>&1
    sudo chmod 640 "$KEYSTORE_PATH/keystore" >> "$LOG_FILE" 2>&1

    # Start Unifi service
    sudo systemctl start unifi >> "$LOG_FILE" 2>&1
    sleep 15

    # Post-check
    NEW_EXPIRY=$(get_keystore_expiry || true)
    if [ -n "$NEW_EXPIRY" ]; then
        log "New Unifi keystore certificate expiry: $NEW_EXPIRY"
    else
        log "Could not verify new Unifi keystore certificate expiry."
    fi
fi

# ==============================================
# Step 6: Final verification
# ==============================================
if systemctl is-active --quiet unifi; then
    log "Unifi Controller is running."
else
    log "Warning: Unifi Controller may not be running!"
    log "Attempting to start Unifi Controller..."
    sudo systemctl start unifi >> "$LOG_FILE" 2>&1
    sleep 10
    if systemctl is-active --quiet unifi; then
        log "Unifi Controller started successfully."
    else
        log "ERROR: Failed to start Unifi Controller. Check logs with: sudo journalctl -u unifi -n 50"
    fi
fi

log "Script completed."