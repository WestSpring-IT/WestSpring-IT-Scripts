#!/bin/bash
set -euo pipefail

# ==============================================
# Configuration
# ==============================================
DOMAIN="omada.westspring-it.co.uk"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
KEYSTORE_PATH="/opt/tplink/EAPController/data/keystore"
P12_FILE="$(date '+%Y_%m')_omada.p12"
PASSWORD="tplink"

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
        -alias eap \
        -keystore "$KEYSTORE_PATH/eap.keystore" \
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
    log "❌ ERROR: Certificate file not found at $CERT_PATH/fullchain.pem"
    exit 1
fi

EXPIRY_LE=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2 | xargs)
DAYS_LE=$(days_until_expiry "$EXPIRY_LE")
log "Let's Encrypt certificate expiry: $EXPIRY_LE ($DAYS_LE day(s) remaining)."

# ==============================================
# Step 2: Get Omada keystore certificate expiry
# ==============================================
EXPIRY_OMADA=""
DAYS_OMADA=9999
if [ -f "$KEYSTORE_PATH/eap.keystore" ]; then
    EXPIRY_OMADA=$(get_keystore_expiry || true)
    if [ -n "$EXPIRY_OMADA" ]; then
        DAYS_OMADA=$(days_until_expiry "$EXPIRY_OMADA")
        log "Omada keystore certificate expiry: $EXPIRY_OMADA ($DAYS_OMADA day(s) remaining)."
    else
        log "⚠️ Could not read expiry date from Omada keystore."
    fi
else
    log "⚠️ Omada keystore not found at $KEYSTORE_PATH/eap.keystore."
fi

# ==============================================
# Step 3: Determine renewal/sync actions
# ==============================================
RENEW=false
APPLY=false

if $FORCE_SYNC; then
    log "🔧 --force-sync flag detected. Forcing Omada keystore rebuild."
    APPLY=true

elif [ "$DAYS_OMADA" -le 7 ]; then
    log "⚠️ Omada keystore certificate expiring soon (<7 days)."
    if [ "$DAYS_LE" -le 7 ]; then
        log "🔄 Let's Encrypt certificate also expiring soon. Renewal required."
        RENEW=true
    else
        log "🔁 Let's Encrypt certificate is still valid. Will reapply it to Omada."
        APPLY=true
    fi
else
    log "✅ Omada keystore certificate valid for more than 7 days. No immediate action needed."
fi

# ==============================================
# Step 4: Renewal (if required)
# ==============================================
if $RENEW; then
    log "Starting Let's Encrypt renewal..."
    sudo tpeap stop >> "$LOG_FILE" 2>&1 || true
    sudo pkill -f "java.*eap" || true
    sudo certbot renew >> "$LOG_FILE" 2>&1

    EXPIRY_LE=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2 | xargs)
    DAYS_LE=$(days_until_expiry "$EXPIRY_LE")
    log "New Let's Encrypt expiry: $EXPIRY_LE ($DAYS_LE day(s) remaining)."
    APPLY=true
fi

# ==============================================
# Step 5: Apply (rebuild Omada keystore)
# ==============================================
if $APPLY; then
    log "Applying Let's Encrypt certificate to Omada Controller..."

    sudo tpeap stop >> "$LOG_FILE" 2>&1 || true
    sudo pkill -f "java.*eap" || true

    sudo rm -f "$KEYSTORE_PATH/eap.keystore" "$KEYSTORE_PATH/eap.cer" >> "$LOG_FILE" 2>&1

    sudo openssl pkcs12 -export \
        -inkey "$CERT_PATH/privkey.pem" \
        -in "$CERT_PATH/cert.pem" \
        -certfile "$CERT_PATH/chain.pem" \
        -name eap \
        -out "$KEYSTORE_PATH/$P12_FILE" \
        -password pass:$PASSWORD >> "$LOG_FILE" 2>&1

    sudo keytool -importkeystore \
        -noprompt \
        -deststorepass $PASSWORD \
        -destkeystore "$KEYSTORE_PATH/eap.keystore" \
        -srckeystore "$KEYSTORE_PATH/$P12_FILE" \
        -srcstoretype PKCS12 \
        -srcstorepass $PASSWORD >> "$LOG_FILE" 2>&1

    sudo tpeap start >> "$LOG_FILE" 2>&1
    sleep 10

    # Post-check
    NEW_EXPIRY=$(get_keystore_expiry || true)
    if [ -n "$NEW_EXPIRY" ]; then
        log "✅ New Omada keystore certificate expiry: $NEW_EXPIRY"
    else
        log "⚠️ Could not verify new Omada keystore certificate expiry."
    fi
fi

# ==============================================
# Step 6: Final verification
# ==============================================
if pgrep -f "java.*eap" > /dev/null; then
    log "✅ Omada Controller is running."
else
    log "⚠️ Warning: Omada Controller may not be running!"
fi

log "Script completed."