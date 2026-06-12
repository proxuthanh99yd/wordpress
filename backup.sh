#!/usr/bin/env bash
#
# backup.sh — Backup database (luôn) và uploads (khi có cờ --uploads) vào ./backups/
#
#   ./backup.sh             # chỉ dump database
#   ./backup.sh --uploads   # dump database + tar uploads
#   KEEP=30 ./backup.sh     # giữ 30 bản gần nhất (mặc định 14)
#
# Chạy định kỳ trên VPS (crontab -e):
#   0 3 * * * /opt/<project>/backup.sh --uploads >> /var/log/wp-backup.log 2>&1

set -euo pipefail

err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }

cd "$(dirname "$0")"

KEEP="${KEEP:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p backups

if [[ -z "$(docker compose ps -q db)" ]]; then
	err "Container db chưa chạy — 'docker-compose up -d' trước."
	exit 1
fi

# ---------------------------------------------------------------------------
# 1. Dump database — credentials lấy từ env CÓ SẴN trong container db,
#    không cần đọc .env trên host
# ---------------------------------------------------------------------------
DB_FILE="backups/db-${STAMP}.sql.gz"
docker compose exec -T db sh -c \
	'mariadb-dump --single-transaction --quick -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
	| gzip > "$DB_FILE"

# Dump rỗng/hỏng = backup vô dụng — kiểm tra trước khi báo thành công
if ! gzip -t "$DB_FILE" 2>/dev/null || [[ "$(wc -c < "$DB_FILE")" -lt 1024 ]]; then
	err "Dump database thất bại hoặc rỗng: $DB_FILE"
	rm -f "$DB_FILE"
	exit 1
fi
ok "DB      → $DB_FILE ($(du -h "$DB_FILE" | cut -f1 | tr -d ' '))"

# ---------------------------------------------------------------------------
# 2. Uploads (tùy chọn)
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--uploads" ]]; then
	if [[ -d public_html/wp-content/uploads ]]; then
		UP_FILE="backups/uploads-${STAMP}.tar.gz"
		tar -czf "$UP_FILE" -C public_html/wp-content uploads
		ok "Uploads → $UP_FILE ($(du -h "$UP_FILE" | cut -f1 | tr -d ' '))"
	else
		err "Không thấy public_html/wp-content/uploads — bỏ qua."
	fi
fi

# ---------------------------------------------------------------------------
# 3. Retention: giữ KEEP bản gần nhất mỗi loại
# ---------------------------------------------------------------------------
for prefix in db uploads; do
	ls -1t "backups/${prefix}-"*.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
		rm -f "$old"
		echo "  đã xoá bản cũ: $old"
	done
done

ok "Backup hoàn tất (giữ tối đa $KEEP bản/loại trong ./backups/)."
