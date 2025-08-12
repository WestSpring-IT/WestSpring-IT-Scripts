#!/bin/bash

# Configuration
DOMAIN="omada.westspring-it.co.uk"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
KEYSTORE_PATH="/opt/tplink/EAPController/data/keystore"
P12_FILE="$(date '+%Y_%m')_omada.p12"
PASSWORD="tplink"

# Generate log file name based on current year and month
LOG_FILE="/home/ubuntu/logs/$(date '+%Y_%m')_ssl_renewal.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check certificate expiry
EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2)
EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_SECONDS=$(date +%s)
DIFF_DAYS=$(( (EXPIRY_SECONDS - CURRENT_SECONDS) / 86400 ))

log "Certificate expires in $DIFF_DAYS day(s)."

if [ "$DIFF_DAYS" -le 7 ]; then
    log "Certificate expiring soon. Starting renewal process..."

# Stop the omada controller
sudo tpeap stop >> "$LOG_FILE"

# Renew the ssl cert
sudo certbot renew >> "$LOG_FILE"

# Remove the existing ssl cert
sudo rm /opt/tplink/EAPController/keystore/eap.cer >> "$LOG_FILE"

# Copy the renewed cert
sudo cp /etc/letsencrypt/live/omada.westspring-it.co.uk/cert.pem /opt/tplink/EAPController/keystore/eap.cer >> "$LOG_FILE"

#Create the private key
sudo openssl pkcs12 -export -inkey /etc/letsencrypt/live/omada.westspring-it.co.uk/privkey.pem \
	-in /etc/letsencrypt/live/omada.westspring-it.co.uk/cert.pem \
	-certfile /etc/letsencrypt/live/omada.westspring-it.co.uk/chain.pem \
	-name eap -out "$KEYSTORE_PATH/$P12_FILE" -password pass:tplink \
	>> "$LOG_FILE"

#Import the private key
sudo keytool -importkeystore \
	-noprompt \
	-deststorepass $PASSWORD \
	-destkeystore "$KEYSTORE_PATH/eap.keystore" \
	-srckeystore "$KEYSTORE_PATH/$P12_FILE" \
	-srcstoretype PKCS12 \
	-srcstorepass $PASSWORD >> "$LOG_FILE"


#Start the omada controller
sudo tpeap start >> "$LOG_FILE"


    log "Renewal process completed."
else
    log "Certificate is valid for more than 7 days. No action taken."
fi
