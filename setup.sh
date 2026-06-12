#!/usr/bin/env bash
#
# setup.sh — Sinh docker-compose.yml và .env theo tên project.
#
# Script hỏi tên project rồi tự tạo:
#   - container names:  <project>, <project>-db, <project>-redis
#   - network:          <project>-network
#   - DB name/user/prefix dẫn xuất từ tên project
#   - mật khẩu ngẫu nhiên (root + db)
#
# Giữ nguyên toàn bộ tối ưu headless (reverse-proxy HTTPS, Redis object cache,
# healthcheck, mu-plugins) — chỉ thay phần định danh theo project.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }

# Chuỗi ngẫu nhiên alnum (không ký tự đặc biệt → an toàn cho .env, không cần quote).
rand() {
	LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-24}" || true
}

confirm() { # confirm "câu hỏi" -> 0 nếu y/Y
	local reply
	read -rp "$1 [y/N]: " reply
	[[ "$reply" =~ ^[yY]$ ]]
}

cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# 1. Nhập thông tin
# ---------------------------------------------------------------------------
read -rp "Tên project (vd: food-inno): " PROJECT
PROJECT="$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
# chỉ giữ a-z 0-9 và dấu '-'
PROJECT="$(printf '%s' "$PROJECT" | tr -cd 'a-z0-9-')"
if [[ -z "$PROJECT" ]]; then
	err "Tên project không hợp lệ."
	exit 1
fi

# slug cho định danh SQL (a-z0-9_)
SLUG="$(printf '%s' "$PROJECT" | tr '-' '_' | tr -cd 'a-z0-9_')"

read -rp "Cổng host expose WordPress [9000]: " HOST_PORT
HOST_PORT="${HOST_PORT:-9000}"

read -rp "WP_SITE_URL (URL công khai của CMS) [http://127.0.0.1:${HOST_PORT}]: " SITE_URL
SITE_URL="${SITE_URL:-http://127.0.0.1:${HOST_PORT}}"

read -rp "FRONTEND_ORIGIN (origin Next.js cho CORS) [http://localhost:3000]: " FRONTEND
FRONTEND="${FRONTEND:-http://localhost:3000}"

# Giá trị dẫn xuất
WP_NAME="$PROJECT"
DB_CONTAINER="${PROJECT}-db"
REDIS_CONTAINER="${PROJECT}-redis"
NETWORK="${PROJECT}-network"
DB_NAME="${SLUG}_db"
DB_USER="${SLUG}_user"
PREFIX="${SLUG}_"
ROOT_PW="$(rand 28)"
DB_PW="$(rand 24)"

info ""
info "Sẽ tạo cấu hình với:"
cat <<SUMMARY
  Project          : $PROJECT
  Containers       : $WP_NAME, $DB_CONTAINER, $REDIS_CONTAINER
  Network          : $NETWORK
  Host port        : 127.0.0.1:$HOST_PORT -> :80
  DB name / user   : $DB_NAME / $DB_USER
  Table prefix     : $PREFIX
  WP_SITE_URL      : $SITE_URL
  FRONTEND_ORIGIN  : $FRONTEND
SUMMARY
info ""

if ! confirm "Tiếp tục?"; then
	err "Đã huỷ."
	exit 1
fi

# ---------------------------------------------------------------------------
# 2. Sinh .env (mật khẩu mới)
# ---------------------------------------------------------------------------
WRITE_ENV=1
if [[ -f .env ]]; then
	err "CẢNH BÁO: .env đã tồn tại."
	err "Tạo mới = mật khẩu DB mới. Nếu mysql-data/ đã khởi tạo, MariaDB sẽ KHÔNG"
	err "nhận mật khẩu mới → login thất bại. Chỉ ghi đè khi chưa 'up' lần nào."
	if ! confirm "Ghi đè .env?"; then
		WRITE_ENV=0
		info "Giữ nguyên .env hiện tại."
	fi
fi

if [[ "$WRITE_ENV" == "1" ]]; then
	cat > .env <<ENV
# Sinh bởi setup.sh — project: $PROJECT
# WordPress Database Configuration
MYSQL_ROOT_PASSWORD=$ROOT_PW
MYSQL_DATABASE=$DB_NAME
MYSQL_USER=$DB_USER
MYSQL_PASSWORD=$DB_PW

# WordPress Table Prefix
WORDPRESS_TABLE_PREFIX=$PREFIX

# Headless CMS
WP_SITE_URL=$SITE_URL
FRONTEND_ORIGIN=$FRONTEND
ENV
	ok "Đã ghi .env"
fi

# ---------------------------------------------------------------------------
# 3. Sinh docker-compose.yml
# ---------------------------------------------------------------------------
if [[ -f docker-compose.yml ]] && ! confirm "Ghi đè docker-compose.yml?"; then
	err "Bỏ qua docker-compose.yml."
else
	# Heredoc trích dẫn ('TEMPLATE') giữ nguyên ${...} và $$ cho Docker/PHP;
	# sed thay các placeholder %%...%% bằng giá trị project.
	cat <<'TEMPLATE' | sed \
		-e "s|%%WP_NAME%%|${WP_NAME}|g" \
		-e "s|%%DB_CONTAINER%%|${DB_CONTAINER}|g" \
		-e "s|%%REDIS_CONTAINER%%|${REDIS_CONTAINER}|g" \
		-e "s|%%NETWORK%%|${NETWORK}|g" \
		-e "s|%%HOST_PORT%%|${HOST_PORT}|g" \
		> docker-compose.yml
services:
  wordpress:
    image: wordpress:6.7-php8.3-apache
    container_name: %%WP_NAME%%
    restart: unless-stopped
    ports:
      - "127.0.0.1:%%HOST_PORT%%:80"
    volumes:
      - ./public_html:/var/www/html
      - ./php-uploads.ini:/usr/local/etc/php/conf.d/uploads.ini
      - ./mu-plugins:/var/www/html/wp-content/mu-plugins:ro
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
      WORDPRESS_TABLE_PREFIX: ${WORDPRESS_TABLE_PREFIX:-wp_}
      WORDPRESS_REDIS_HOST: redis
      WORDPRESS_REDIS_PORT: 6379
      WP_SITE_URL: ${WP_SITE_URL:-}
      FRONTEND_ORIGIN: ${FRONTEND_ORIGIN:-}
      WORDPRESS_CONFIG_EXTRA: |
        /* Reverse proxy: trust X-Forwarded-Proto so WP serves HTTPS URLs (chống redirect loop) */
        if ( isset($$_SERVER['HTTP_X_FORWARDED_PROTO']) && $$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
            $$_SERVER['HTTPS'] = 'on';
        }
        /* Headless site URLs */
        if ( getenv('WP_SITE_URL') ) {
            define('WP_HOME', getenv('WP_SITE_URL'));
            define('WP_SITEURL', getenv('WP_SITE_URL'));
        }
        /* Frontend origin dùng cho CORS mu-plugin */
        if ( getenv('FRONTEND_ORIGIN') ) {
            define('HEADLESS_FRONTEND_ORIGIN', getenv('FRONTEND_ORIGIN'));
        }
        /* Bảo mật: chặn sửa file plugin/theme trong admin */
        define('DISALLOW_FILE_EDIT', true);
    healthcheck:
      # Image WordPress không chắc có `curl`; dùng php (luôn có) để kiểm tra port 80
      test: ["CMD-SHELL", "php -r 'exit(@fsockopen(\"localhost\", 80) ? 0 : 1);'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - %%NETWORK%%

  db:
    image: mariadb:10.11
    container_name: %%DB_CONTAINER%%
    restart: unless-stopped
    volumes:
      - ./mysql-data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - %%NETWORK%%

  redis:
    image: redis:7-alpine
    container_name: %%REDIS_CONTAINER%%
    restart: unless-stopped
    # Object cache là ephemeral: bỏ AOF, giới hạn RAM và evict LRU thay vì phình/OOM
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru --save "" --appendonly no
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - %%NETWORK%%

networks:
  %%NETWORK%%:
    driver: bridge
TEMPLATE
	ok "Đã ghi docker-compose.yml"
fi

info ""
ok "Hoàn tất. Tiếp theo:"
echo "  1. docker-compose up -d"
echo "  2. Cài plugin Redis Object Cache (+ Enable) và WPGraphQL — xem README-REDIS.md"
