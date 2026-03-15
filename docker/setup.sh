#!/bin/bash
# Arlo Open Base Station — one-time Docker setup
# Run from anywhere: bash docker/setup.sh  (or  ./docker/setup.sh)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[setup]${NC} $*"; }
error() { echo -e "${RED}[setup]${NC} $*"; exit 1; }

# ── Prerequisite checks ───────────────────────────────────────────────────────
info "Checking prerequisites..."
command -v docker   >/dev/null 2>&1 || error "docker not found. Install Docker Desktop: https://docs.docker.com/desktop/windows/"
docker compose version >/dev/null 2>&1 || error "'docker compose' (v2) not found. Update Docker Desktop to a recent version."
command -v openssl  >/dev/null 2>&1 || error "openssl not found. Install Git for Windows (includes openssl) or WSL2."
info "Prerequisites OK."

echo ""
echo "======================================================================"
echo " Arlo Open Base Station — Docker Setup"
echo "======================================================================"
echo ""
echo " This script will:"
echo "   1. Prompt for your Windows PC's WiFi IP and a web UI password"
echo "   2. Generate a self-signed TLS certificate"
echo "   3. Generate random secrets for session auth and thumbnail signing"
echo "   4. Create docker/config.yaml and docker/.env"
echo ""
echo " To find your Windows WiFi IP, open PowerShell and run:"
echo "   ipconfig | findstr /i 'IPv4'"
echo " Look for the address on your WiFi adapter (e.g. 192.168.1.50)."
echo ""
echo "======================================================================"
echo ""

# ── Prompt for HOST_IP ────────────────────────────────────────────────────────
while true; do
    read -r -p "Enter your Windows PC WiFi IP address (e.g. 192.168.1.50): " HOST_IP
    if [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    warn "Invalid IP address. Please enter a valid IPv4 address."
done

# ── Prompt for AUTH_PASSWORD ──────────────────────────────────────────────────
while true; do
    read -r -s -p "Enter web UI password (no spaces or quotes): " AUTH_PASSWORD
    echo ""
    if [ -z "$AUTH_PASSWORD" ]; then
        warn "Password cannot be empty."
        continue
    fi
    if [[ "$AUTH_PASSWORD" == *" "* ]] || [[ "$AUTH_PASSWORD" == *"'"* ]] || [[ "$AUTH_PASSWORD" == *'"'* ]]; then
        warn "Password must not contain spaces or quotes."
        continue
    fi
    read -r -s -p "Confirm password: " AUTH_PASSWORD2
    echo ""
    if [ "$AUTH_PASSWORD" = "$AUTH_PASSWORD2" ]; then
        break
    fi
    warn "Passwords do not match. Try again."
done

# ── Generate TLS certificate ──────────────────────────────────────────────────
CERTS_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERTS_DIR"

if [ -f "$CERTS_DIR/key.pem" ] && [ -f "$CERTS_DIR/cert.pem" ]; then
    warn "TLS certificates already exist in docker/certs/ — skipping generation."
else
    info "Generating self-signed TLS certificate (10-year validity)..."
    # MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from mangling the /CN= subject as a file path
    MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:4096 \
        -keyout "$CERTS_DIR/key.pem" \
        -out    "$CERTS_DIR/cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=arlo-base-station" \
        -addext "subjectAltName=IP:${HOST_IP}" \
        2>/dev/null
    info "Certificates written to docker/certs/"
fi

# ── Generate random secrets ───────────────────────────────────────────────────
info "Generating random secrets..."
AUTH_SECRET="$(MSYS_NO_PATHCONV=1 openssl rand -hex 32)"
THUMBNAIL_SECRET="$(MSYS_NO_PATHCONV=1 openssl rand -hex 32)"

# ── Write docker/.env ─────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
cat > "$ENV_FILE" <<EOF
HOST_IP=${HOST_IP}
AUTH_PASSWORD=${AUTH_PASSWORD}
AUTH_SECRET=${AUTH_SECRET}
THUMBNAIL_SECRET=${THUMBNAIL_SECRET}
EOF
info "Written: docker/.env"

# ── Create docker/config.yaml from template ───────────────────────────────────
CONFIG_TEMPLATE="$SCRIPT_DIR/../config/config.yaml.example"
CONFIG_OUT="$SCRIPT_DIR/config.yaml"

if [ ! -f "$CONFIG_TEMPLATE" ]; then
    error "Template not found: config/config.yaml.example"
fi

if [ -f "$CONFIG_OUT" ]; then
    warn "docker/config.yaml already exists — skipping (edit manually if needed)."
else
    cp "$CONFIG_TEMPLATE" "$CONFIG_OUT"
    # Set RecordingBasePath to the Docker volume mount
    sed -i 's|RecordingBasePath:.*|RecordingBasePath: "/recordings/"|' "$CONFIG_OUT"
    # Inject the generated thumbnail secret
    sed -i "s|ThumbnailSecret:.*|ThumbnailSecret: \"${THUMBNAIL_SECRET}\"|" "$CONFIG_OUT"
    # Set thumbnail base URL so ntfy notifications include clickable thumbnails
    sed -i "s|NtfyThumbnailBaseUrl:.*|NtfyThumbnailBaseUrl: \"https://${HOST_IP}:3003/api/thumbnail\"|" "$CONFIG_OUT"
    # Set viewer click URL
    sed -i "s|NtfyClickUrl:.*|NtfyClickUrl: \"https://${HOST_IP}:3003\"|" "$CONFIG_OUT"
    info "Written: docker/config.yaml"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "======================================================================"
echo -e " ${GREEN}Setup complete!${NC}"
echo "======================================================================"
echo ""
echo " Next steps:"
echo ""
echo " 1. Edit docker/config.yaml to customise settings:"
echo "      - Add your camera serial numbers under CameraAliases"
echo "      - Configure NtfyTopic (optional push notifications)"
echo "      - Leave RecordingBasePath as /recordings/"
echo ""
echo " 2. Configure your home router to use ${HOST_IP} as the DNS server"
echo "    for DHCP clients (or just for the Arlo camera's static entry)."
echo "    See docker/README.md for detailed instructions."
echo ""
echo " 3. Build and start the containers:"
echo "      cd docker"
echo "      docker compose up --build"
echo ""
echo " 4. Open the web UI (accept the self-signed cert warning):"
echo "      https://${HOST_IP}:3003"
echo ""
echo " 5. Power on your Arlo camera — it should register within 30 seconds."
echo "    Watch cam-api logs for: 'Registration from <SERIAL>'"
echo ""
echo " To stop: Ctrl+C  (or: docker compose down)"
echo " To run in background: docker compose up --build -d"
echo ""
