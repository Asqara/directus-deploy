#!/usr/bin/env bash
# =============================================================
#  setup.sh - Instalasi otomatis Directus di Ubuntu/Debian
#
#  Pemakaian:
#     sudo DOMAIN=cms.asqara.tech EMAIL=admin@asqara.tech ./setup.sh
#
#  Di VM lokal (tanpa domain & HTTPS), pakai IP VM:
#     sudo DOMAIN=192.168.56.10 SKIP_SSL=1 ./setup.sh
#
#  Yang dilakukan script ini:
#     1. Instal Docker, Nginx, Certbot
#     2. Membuat file .env berisi password acak yang kuat
#     3. Menjalankan Directus + PostgreSQL + Redis
#     4. Memasang Nginx sebagai reverse proxy
#     5. Memasang sertifikat HTTPS gratis (Let's Encrypt)
# =============================================================
set -euo pipefail

DOMAIN="${DOMAIN:-cms.asqara.tech}"
EMAIL="${EMAIL:-admin@asqara.tech}"
SKIP_SSL="${SKIP_SSL:-0}"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
# Tanpa SSL (mis. di VM lokal) -> pakai http
if [ "$SKIP_SSL" = "1" ]; then SCHEME=http; else SCHEME=https; fi

hijau()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
kuning() { printf '\033[1;33m%s\033[0m\n' "$*"; }
merah()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
langkah(){ echo; hijau "==> $*"; }

[ "$(id -u)" -eq 0 ] || { merah "Jalankan dengan sudo: sudo ./setup.sh"; exit 1; }
cd "$APP_DIR"

# ---------------------------------------------------------------
langkah "1/6 Memperbarui paket & menginstal kebutuhan dasar"
apt-get update -y
apt-get install -y ca-certificates curl gnupg openssl nginx certbot python3-certbot-nginx

# ---------------------------------------------------------------
langkah "2/6 Menginstal Docker Engine + Docker Compose"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  kuning "Docker sudah terpasang: $(docker --version)"
else
  . /etc/os-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# ---------------------------------------------------------------
langkah "3/6 Menyiapkan konfigurasi (.env) & folder data"
if [ ! -f .env ]; then
  ADMIN_PASS="$(openssl rand -base64 18 | tr -d '/+=')"
  sed -e "s|^PUBLIC_URL=.*|PUBLIC_URL=${SCHEME}://${DOMAIN}|" \
      -e "s|^SECRET=.*|SECRET=$(openssl rand -hex 32)|" \
      -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -hex 24)|" \
      -e "s|^ADMIN_EMAIL=.*|ADMIN_EMAIL=${EMAIL}|" \
      -e "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${ADMIN_PASS}|" \
      .env.example > .env
  chmod 600 .env
  hijau ".env dibuat dengan password acak."
else
  kuning ".env sudah ada, tidak ditimpa."
fi
mkdir -p data/database uploads extensions backups
# Container Directus berjalan sebagai user 'node' (UID 1000)
chown -R 1000:1000 uploads extensions

# ---------------------------------------------------------------
langkah "4/6 Menjalankan container Directus"
docker compose pull
docker compose up -d
printf 'Menunggu Directus siap'
for _ in $(seq 1 60); do
  if curl -fs "http://127.0.0.1:8055/server/ping" >/dev/null; then echo; hijau "Directus berjalan!"; break; fi
  printf '.'; sleep 3
done
curl -fs "http://127.0.0.1:8055/server/ping" >/dev/null || { merah "Directus belum merespons. Cek: docker compose logs directus"; exit 1; }

# ---------------------------------------------------------------
langkah "5/6 Mengonfigurasi Nginx untuk ${DOMAIN}"
sed "s/cms\.asqara\.tech/${DOMAIN}/g" nginx/cms.asqara.tech.conf > "/etc/nginx/sites-available/${DOMAIN}"
ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
nginx -t
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  # Nginx belum jalan. Penyebab paling umum: port 80/443 sudah dipakai program lain.
  BENTROK="$(ss -Htlnp '( sport = :80 or sport = :443 )' | grep -v nginx || true)"
  if [ -n "$BENTROK" ]; then
    merah "Nginx tidak bisa jalan karena port 80/443 sudah dipakai program lain:"
    echo "$BENTROK"
    kuning "Hentikan program tersebut (mis. sudo systemctl disable --now apache2), lalu jalankan ulang setup.sh."
    exit 1
  fi
  systemctl enable --now nginx
fi

# Buka port web jika firewall UFW aktif (tidak mengaktifkan UFW otomatis)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 'Nginx Full'
fi

# ---------------------------------------------------------------
langkah "6/6 Memasang sertifikat HTTPS (Let's Encrypt)"
if [ "$SKIP_SSL" = "1" ]; then
  kuning "Dilewati (SKIP_SSL=1)."
else
  certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --non-interactive --redirect
fi

# ---------------------------------------------------------------
# shellcheck disable=SC1091
. ./.env
echo
hijau "============================================================"
hijau "  INSTALASI SELESAI!"
hijau "============================================================"
echo "  URL Admin : ${SCHEME}://${DOMAIN}/admin"
echo "  Email     : ${ADMIN_EMAIL}"
echo "  Password  : ${ADMIN_PASSWORD}"
echo
kuning "  Simpan password di atas, lalu segera ganti setelah login."
