#!/usr/bin/env bash
#
# wp-init.sh — Tự động cài WordPress sau khi `docker-compose up -d`:
#   1. Chờ container wordpress healthy
#   2. Cài WP-CLI (phar) vào container
#   3. wp core install (admin user/password tự sinh nếu để trống)
#   4. Đặt permalink /%postname%/ — BẮT BUỘC cho headless: REST /wp-json
#      trả 404 với permalink "plain" mặc định
#   5. Cài + kích hoạt Redis Object Cache (enable drop-in) và WPGraphQL
#
# Chạy lại an toàn (idempotent): bước nào xong rồi sẽ bỏ qua.

set -euo pipefail

err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }

rand() {
	LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-24}" || true
}

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
	err "Không thấy .env — chạy ./setup.sh trước."
	exit 1
fi

# ---------------------------------------------------------------------------
# 1. Chờ wordpress healthy
# ---------------------------------------------------------------------------
CID="$(docker compose ps -q wordpress || true)"
if [[ -z "$CID" ]]; then
	err "Container wordpress chưa chạy — chạy 'docker-compose up -d' trước."
	exit 1
fi

info "Chờ container wordpress healthy..."
for _ in $(seq 1 36); do
	STATUS="$(docker inspect -f '{{.State.Health.Status}}' "$CID" 2>/dev/null || echo unknown)"
	[[ "$STATUS" == "healthy" ]] && break
	sleep 5
done
if [[ "${STATUS:-}" != "healthy" ]]; then
	err "wordpress không healthy sau 3 phút (status: ${STATUS:-unknown}). Xem: docker-compose logs wordpress"
	exit 1
fi
ok "wordpress healthy."

# ---------------------------------------------------------------------------
# 2. WP-CLI trong container (chạy bằng user www-data, HOME ghi được)
# ---------------------------------------------------------------------------
# </dev/null: chặn docker exec -T nuốt stdin của script (làm hỏng các lệnh read phía sau)
wpexec() { docker compose exec -T -e HOME=/tmp -u www-data wordpress "$@" </dev/null; }
wp()     { wpexec php -d memory_limit=512M /tmp/wp-cli.phar --path=/var/www/html "$@"; }

if ! wpexec test -f /tmp/wp-cli.phar; then
	info "Tải WP-CLI vào container..."
	wpexec php -r "copy('https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar', '/tmp/wp-cli.phar');"
fi
wp --version >/dev/null || { err "WP-CLI không chạy được."; exit 1; }

# ---------------------------------------------------------------------------
# 3. wp core install (bỏ qua nếu đã cài)
# ---------------------------------------------------------------------------
SITE_URL="$(grep -E '^WP_SITE_URL=' .env | cut -d= -f2- || true)"
SITE_URL="${SITE_URL:-http://127.0.0.1:9000}"

if wp core is-installed 2>/dev/null; then
	info "WordPress đã được cài — bỏ qua core install."
else
	# `|| true`: stdin EOF (chạy không tương tác) thì dùng default thay vì thoát vì set -e
	read -rp "Site title [Headless CMS]: " TITLE || true
	TITLE="${TITLE:-Headless CMS}"
	read -rp "Admin user [admin]: " ADMIN_USER || true
	ADMIN_USER="${ADMIN_USER:-admin}"
	read -rp "Admin email [admin@example.com]: " ADMIN_EMAIL || true
	ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
	read -rp "Admin password [tự sinh ngẫu nhiên]: " ADMIN_PASS || ADMIN_PASS=""
	if [[ -z "$ADMIN_PASS" ]]; then
		ADMIN_PASS="$(rand 20)"
		GENERATED_PASS=1
	fi

	wp core install \
		--url="$SITE_URL" \
		--title="$TITLE" \
		--admin_user="$ADMIN_USER" \
		--admin_password="$ADMIN_PASS" \
		--admin_email="$ADMIN_EMAIL" \
		--skip-email
	ok "Đã cài WordPress: $SITE_URL"
	if [[ "${GENERATED_PASS:-}" == "1" ]]; then
		ok ">>> Admin password (LƯU LẠI NGAY, chỉ hiện 1 lần): $ADMIN_PASS"
	fi
fi

# ---------------------------------------------------------------------------
# 4. Permalink — REST API /wp-json cần pretty permalinks
# ---------------------------------------------------------------------------
CURRENT_PERMALINK="$(wp option get permalink_structure || true)"
if [[ -z "$CURRENT_PERMALINK" ]]; then
	wp rewrite structure '/%postname%/' --hard
	ok "Đã đặt permalink /%postname%/ (bắt buộc cho /wp-json)."
else
	info "Permalink đã đặt: $CURRENT_PERMALINK — bỏ qua."
fi

# ---------------------------------------------------------------------------
# 5. Plugins headless
# ---------------------------------------------------------------------------
info "Cài plugins: redis-cache, wp-graphql..."
wp plugin install redis-cache wp-graphql --activate 2>&1 | grep -vE '^$' || true

# Enable Redis object cache drop-in (tạo wp-content/object-cache.php)
if wp redis status 2>/dev/null | grep -qi 'Connected'; then
	info "Redis object cache đã connected — bỏ qua."
else
	wp redis enable
fi
wp redis status | head -5 || true

info ""
ok "Hoàn tất. Kiểm tra nhanh:"
echo "  - REST API : ${SITE_URL%/}/wp-json/"
echo "  - GraphQL  : ${SITE_URL%/}/graphql"
echo "  - Admin    : ${SITE_URL%/}/wp-admin/"
