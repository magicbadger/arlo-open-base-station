# Arlo Open Base Station — Docker on Windows

Run `arlo-cam-api` (Python/Flask) and `arlo-viewer` (Node.js) in Docker Desktop on Windows, with both the Windows PC and the Arlo camera on the same home WiFi network.

## Architecture

```
Home WiFi (192.168.x.x)
│
├── Windows PC (HOST_IP, e.g. 192.168.1.50)
│   └── Docker Compose
│       ├── cam-api container
│       │   ├─ port 4000 → Windows:4000   (camera control protocol)
│       │   └─ port 53/UDP → Windows:53   (DNS: gateway.arlo → HOST_IP)
│       └── viewer container
│           └─ port 3003 → Windows:3003   (HTTPS web UI)
│
└── Arlo Camera
    ├── Connected to home WiFi
    ├── DNS set to Windows PC IP (via router or static assignment)
    ├── Resolves gateway.arlo → HOST_IP via dnsmasq inside cam-api
    └── Connects to HOST_IP:4000 → cam-api container
```

The `viewer` proxies API calls to `cam-api` using Docker's internal DNS name `cam-api:5000`. Port 5000 is not exposed to the host.

---

## Prerequisites

- **Docker Desktop** for Windows (WSL2 backend): https://docs.docker.com/desktop/windows/
- **Git for Windows** (provides Git Bash + openssl): https://git-scm.com/downloads
- Docker Compose v2 (included with Docker Desktop)

---

## One-time Setup

Open Git Bash (or WSL2) in the repository root and run:

```bash
bash docker/setup.sh
```

The script will:
1. Ask for your **Windows PC WiFi IP** (find it with `ipconfig | findstr "IPv4"`)
2. Ask for a **web UI password**
3. Generate a self-signed TLS certificate → `docker/certs/`
4. Generate random secrets for session auth and thumbnail HMAC signing
5. Write `docker/.env` and `docker/config.yaml`

After setup, edit `docker/config.yaml` to:
- Add your camera serial numbers under `CameraAliases`
- Configure `NtfyTopic` if you want push notifications (optional)

### Finding your camera serial number

- **Physical label** — sticker on the back or bottom of the camera
- **Original box** — printed on the barcode label
- **Arlo app** — Settings → Camera Settings → Device Info (if previously paired with the cloud app)
- **From the logs** — the easiest method if you don't have the above: start the containers, power on the camera, and watch the logs:
  ```bash
  docker compose logs -f cam-api
  ```
  You'll see a line like:
  ```
  Registration from 4HG12345678A - VMC5040
  ```
  That alphanumeric string is the serial number. Stop the containers, add it to `config.yaml` under `CameraAliases`, then restart.

---

## Configure Camera DNS

The Arlo camera discovers the base station by resolving the hostname `gateway.arlo`. The `cam-api` container runs dnsmasq to answer this query with your Windows PC's IP.

You need to point the camera's DNS server at your Windows PC. Two options:

### Option A — Home Router (Recommended)

In your router's admin panel, set the **DHCP DNS server** to your Windows PC's WiFi IP (e.g. `192.168.1.50`). This applies to all devices including the camera.

The location varies by router:
- **TP-Link**: DHCP → DHCP Settings → Primary DNS
- **ASUS**: LAN → DHCP Server → DNS Server 1
- **Netgear**: Advanced → Setup → Internet Setup → DNS Addresses
- **Ubiquiti/UniFi**: Networks → [Your network] → DHCP → DNS Server

### Option B — Static DHCP Entry for Camera

If you cannot change the router-wide DNS, assign the camera a static IP/DNS entry:
1. Find the camera's MAC address in your router's client list
2. Create a static DHCP reservation for it
3. Set the DNS for that reservation to the Windows PC IP

> **Note:** Not all routers support per-client DNS settings in static reservations.

---

## Port 53 Conflict — Required Windows Fix

On most Windows machines, the Windows DNS Client (`svchost` hosting `Dnscache`) binds to **`0.0.0.0:53`**, which blocks Docker from forwarding port 53 UDP to the container.

### Check what's on port 53

Open PowerShell and run:

```powershell
Get-NetUDPEndpoint -LocalPort 53 | Format-Table LocalAddress, LocalPort, OwningProcess
```

If you see `svchost` at `0.0.0.0:53`, choose one of the two options below.

> **Note:** The `ListenAddresses` registry key (`HKLM:\...\Dnscache\Parameters`) is documented online but is **not honored** by Windows 10/11. It has no effect even after a reboot.

### Option A — Disable the Windows DNS Client service (Recommended)

The DNS Client service (`Dnscache`) is a **cache only** — it is not required for DNS resolution. Windows will still resolve DNS normally by sending queries directly to the configured DNS server. Disabling it frees port 53 for Docker.

Open PowerShell **as Administrator**:

```powershell
# Stop and disable the DNS Client cache service
Stop-Service -Name Dnscache -Force
Set-Service -Name Dnscache -StartupType Disabled
```

Verify port 53 is now free:
```powershell
Get-NetUDPEndpoint -LocalPort 53
```

The output should be empty (or show only loopback entries). Now start or restart the Docker containers — port 53 mapping will work.

**To re-enable the DNS Client later (if needed):**
```powershell
Set-Service -Name Dnscache -StartupType Automatic
Start-Service -Name Dnscache
```

### Option B — Add a custom DNS record on your router

If you prefer not to change Windows services, configure `gateway.arlo` as a custom DNS record directly in your router's admin panel. This way dnsmasq in the container is not needed at all.

Look for a setting called **Custom DNS Records**, **Local DNS**, or **Static DNS** in your router admin UI:

| Router brand | Where to find it |
|---|---|
| **Ubiquiti/UniFi** | Network → DNS → Local Domain Records |
| **pfSense/OPNsense** | Services → DNS Resolver → Host Overrides |
| **TP-Link Omada** | Settings → Network → Static DNS |
| **DD-WRT** | Services → Services → DNSMasq → Additional Options |
| **OpenWrt** | Network → DHCP and DNS → Hostnames |

Add a record: `gateway.arlo` → `<your Windows PC IP>`

This approach requires no changes to Windows and no port 53 forwarding in Docker (you can remove the `"53:53/udp"` port mapping from `docker-compose.yml` if you use this option).

---

## Running

```bash
cd docker
docker compose up --build
```

The `--build` flag rebuilds images on first run (takes a few minutes). On subsequent runs you can omit it.

Watch for these messages in the logs:
- `cam-api: [entrypoint] Starting dnsmasq: gateway.arlo -> 192.168.1.50`
- `cam-api: [entrypoint] Starting arlo-cam-api...`
- `viewer: Arlo Viewer HTTPS server running on port 3003`

**To run in the background:**
```bash
docker compose up --build -d
docker compose logs -f   # follow logs
```

**To stop:**
```bash
docker compose down      # stops containers, volumes persist
docker compose down -v   # stops containers AND deletes volumes (loses recordings + DB)
```

---

## Access the Web UI

Once running, open in your Windows browser:

```
https://192.168.1.50:3003
```

You'll see a browser warning about the self-signed certificate. Click **Advanced → Proceed** (Chrome) or **Accept the Risk** (Firefox).

Log in with the password you set during setup.

---

## Camera Registration

Power on your Arlo camera. If DNS is configured correctly, you should see within 30 seconds:

```
cam-api  | Registration from <YOUR_SERIAL> - VMC5040
```

If the camera doesn't register:
1. Verify DNS is pointing at the Windows PC: on another device on the same WiFi, run `nslookup gateway.arlo 192.168.1.50` — it should return the Windows PC IP.
2. Check port 4000 is reachable: `Test-NetConnection -ComputerName 192.168.1.50 -Port 4000` from PowerShell.
3. Check Windows Firewall isn't blocking port 4000 or 53.

---

## Data Persistence

| Data | Storage | Notes |
|------|---------|-------|
| SQLite database | Docker volume `arlo_data` | Camera registrations, state |
| Video recordings | Docker volume `arlo_recordings` | `.mkv` files + thumbnails |
| Config | `docker/config.yaml` (bind mount) | Edit on host, restart to apply |
| TLS certs | `docker/certs/` (bind mount) | Regenerate with `setup.sh` |

Volumes survive `docker compose restart` and `docker compose down`. They are deleted by `docker compose down -v`.

---

## Updating

```bash
# Pull latest code
git pull

# Rebuild and restart
cd docker
docker compose up --build -d
```

Config and recordings are preserved in volumes/bind mounts.

---

## Firewall Notes (Windows)

Docker Desktop creates a firewall rule for mapped ports automatically, but if your camera can't connect, add rules manually in PowerShell (Administrator):

```powershell
# Allow camera control
netsh advfirewall firewall add rule name="Arlo cam-api" dir=in action=allow protocol=tcp localport=4000

# Allow DNS
netsh advfirewall firewall add rule name="Arlo DNS" dir=in action=allow protocol=udp localport=53

# Allow web UI
netsh advfirewall firewall add rule name="Arlo viewer" dir=in action=allow protocol=tcp localport=3003
```

---

## Troubleshooting

**Container won't start — port 53 in use:**
```powershell
# PowerShell: find what's using port 53
netstat -anou | findstr ":53 "
# Get process name from PID
Get-Process -Id <PID>
```

**Camera registers but no recordings appear:**
- Check `docker/config.yaml` has `RecordOnMotionAlert: true`
- Trigger motion and watch cam-api logs: `docker compose logs -f cam-api`

**Web UI shows "Failed to fetch camera status":**
- Check cam-api is healthy: `docker compose ps`
- Verify viewer can reach cam-api: `docker compose exec viewer wget -qO- http://cam-api:5000/cameras/status`

**VLC audio recording not working:**
- Audio recording (`audioAlert`) is disabled by default (`RecordOnAudioAlert: false`)
- VLC in Docker may have issues with audio devices; use ffmpeg-based motion recording instead

**Reset everything:**
```bash
docker compose down -v   # removes volumes (DB + recordings)
rm docker/.env docker/config.yaml docker/certs/key.pem docker/certs/cert.pem
bash docker/setup.sh
```
