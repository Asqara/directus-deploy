#!/usr/bin/env bash
# =============================================================
#  backup.sh - Backup database + file upload Directus
#
#  Pemakaian manual :  ./scripts/backup.sh
#  Otomatis (cron)  :  0 2 * * * /opt/directus/scripts/backup.sh
#  Hasil disimpan di folder backups/, backup >7 hari dihapus.
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. ./.env

STAMP="$(date +%Y%m%d-%H%M%S)"
KEEP_DAYS="${KEEP_DAYS:-7}"
mkdir -p backups

echo "==> Backup database..."
docker compose exec -T database pg_dump -U "$DB_USER" -d "$DB_DATABASE" --clean --if-exists \
  | gzip > "backups/db-${STAMP}.sql.gz"

echo "==> Backup file upload..."
tar -czf "backups/uploads-${STAMP}.tar.gz" uploads

echo "==> Menghapus backup lebih dari ${KEEP_DAYS} hari..."
find backups -type f -mtime +"$KEEP_DAYS" -delete

echo "Selesai:"
ls -lh backups | tail -n 4
