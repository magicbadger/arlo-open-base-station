#!/bin/bash
set -e

if [ -z "$HOST_IP" ]; then
    echo "ERROR: HOST_IP environment variable is not set."
    echo "Set HOST_IP to your Windows PC's WiFi IP address in docker/.env"
    exit 1
fi

echo "[entrypoint] Starting dnsmasq: gateway.arlo -> ${HOST_IP}"

# Start dnsmasq in DNS-only mode:
#   - Resolves gateway.arlo → HOST_IP (camera discovery)
#   - Forwards all other queries to the upstream DNS from /etc/resolv.conf
#   - No DHCP (dnsmasq does not do DHCP without dhcp-range config)
dnsmasq --no-daemon \
    --port=53 \
    --address=/gateway.arlo/${HOST_IP} \
    --listen-address=0.0.0.0 &

echo "[entrypoint] Starting arlo-cam-api..."
exec python /app/server.py
