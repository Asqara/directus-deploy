#!/usr/bin/env bash
# =============================================================
#  restore.sh - Mengembalikan database (+ upload) dari backup
#
#  Pemakaian:
#     ./scripts/restore.sh backups/db-20260929-020000.sql.gz [backups/uploads-20260929-020000.tar.gz]
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. ./.env

DB_FILE="${1:?Sebutkan file backup database, contoh: backups/db-xxxx.sql.gz}"
UPLOADS_FILE="${2:-}"

read -r -p "Data sekarang akan DITIMPA oleh backup. Lanjut? (y/N) " jawab
[ "$jawab" = "y" ] || { echo "Dibatalkan."; exit 0; }

echo "==> Menghentikan Directus sementara..."
docker compose stop directus

echo "==> Restore database dari $DB_FILE ..."
gunzip -c "$DB_FILE" | docker compose exec -T database psql -q -o /dev/null -U "$DB_USER" -d "$DB_DATABASE"

if [ -n "$UPLOADS_FILE" ]; then
  echo "==> Restore file upload dari $UPLOADS_FILE ..."
  tar -xzf "$UPLOADS_FILE"
fi

echo "==> Menyalakan kembali Directus..."
docker compose start directus
echo "Restore selesai."
