#!/bin/bash

# Reality keys initialization script
echo "[REALITY-INIT] Setting up Reality keys..."

# Generate Reality keys if not provided
if [ -z "$XRAY_REALITY_PRIVATE_KEY" ] || [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
    echo "[REALITY-INIT] Generating new Reality key pair..."
    
    # Generate key pair using xray
    KEY_OUTPUT=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep "Public key:" | awk '{print $3}')
    
    if [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ]; then
        export XRAY_REALITY_PRIVATE_KEY="$PRIVATE_KEY"
        export XRAY_REALITY_PUBLIC_KEY="$PUBLIC_KEY"
        
        # Save keys to file for persistence
        echo "XRAY_REALITY_PRIVATE_KEY=$PRIVATE_KEY" > /var/lib/marzban/reality_keys.env
        echo "XRAY_REALITY_PUBLIC_KEY=$PUBLIC_KEY" >> /var/lib/marzban/reality_keys.env
        
        echo "[REALITY-INIT] Generated new Reality keys"
        echo "[REALITY-INIT] Private: $PRIVATE_KEY"
        echo "[REALITY-INIT] Public: $PUBLIC_KEY"
    else
        echo "[REALITY-INIT] ERROR: Failed to generate Reality keys"
        exit 1
    fi
else
    echo "[REALITY-INIT] Using provided Reality keys"
fi

# Set default Reality server names if not provided
if [ -z "$XRAY_REALITY_SERVER_NAMES" ]; then
    export XRAY_REALITY_SERVER_NAMES="google.com,www.google.com"
    echo "[REALITY-INIT] Using default server names: $XRAY_REALITY_SERVER_NAMES"
fi

# Set default short IDs if not provided
if [ -z "$XRAY_REALITY_SHORT_IDS" ]; then
    # Generate random short IDs
    SHORT_ID1=$(openssl rand -hex 8)
    SHORT_ID2=$(openssl rand -hex 8)
    export XRAY_REALITY_SHORT_IDS="$SHORT_ID1,$SHORT_ID2"
    echo "[REALITY-INIT] Generated short IDs: $XRAY_REALITY_SHORT_IDS"
fi

echo "[REALITY-INIT] Reality setup completed"