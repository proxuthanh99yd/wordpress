#!/usr/bin/env bash
#
# setup.sh — Dashboard quản lý WordPress Headless CMS.
#
#   ./setup.sh            # mở dashboard (menu tương tác)
#   ./setup.sh wizard     # chạy thẳng wizard cài đặt mới
#   ./setup.sh up|down|restart|status|backup|init|nginx
#                         # chạy thẳng 1 tác vụ, không vào menu
#
# Kiến trúc: wp-init.sh (cài WP + plugins) và backup.sh (dump DB/uploads)
# vẫn là script standalone — dashboard chỉ gọi lại chúng.

set -euo pipefail

cd "$(dirname "$0")"

# ===========================================================================
# UI helpers
# ===========================================================================
C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_CYN=$'\033[36m'
C_DIM=$'\033[2m';  C_BLD=$'\033[1m';  C_RST=$'\033[0m'

err()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RST" >&2; }
ok()   { printf '%s✓ %s%s\n' "$C_GRN" "$*" "$C_RST"; }
info() { printf '%s→ %s%s\n' "$C_CYN" "$*" "$C_RST"; }

step() { # step <n> <total> "tiêu đề"
	printf '\n%s── [%s/%s] %s %s%s\n' "$C_BLD" "$1" "$2" "$3" \
		"$(printf '─%.0s' $(seq 1 $((40 - ${#3}))))" "$C_RST"
}

ask() { # ask VAR "câu hỏi" "default" — Enter/EOF = default
	local __var="$1" __q="$2" __def="${3:-}" __ans=""
	if [[ -n "$__def" ]]; then
		printf '%s%s%s %s[%s]%s: ' "$C_CYN" "$__q" "$C_RST" "$C_DIM" "$__def" "$C_RST"
	else
		printf '%s%s%s: ' "$C_CYN" "$__q" "$C_RST"
	fi
	read -r __ans || true
	printf -v "$__var" '%s' "${__ans:-$__def}"
}

confirm() { # confirm "câu hỏi" -> 0 nếu y/Y
	local reply=""
	printf '%s%s%s %s[y/N]%s: ' "$C_CYN" "$1" "$C_RST" "$C_DIM" "$C_RST"
	read -r reply || true
	[[ "$reply" =~ ^[yY]$ ]]
}

pause() {
	printf '%s(Enter để tiếp tục)%s' "$C_DIM" "$C_RST"
	read -r _ || true
	echo
}

# Chuỗi ngẫu nhiên alnum (không ký tự đặc biệt → an toàn cho .env, không cần quote).
rand() {
	LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-24}" || true
}

banner() {
	printf '%s' "$C_CYN"
	cat <<'B'
╔══════════════════════════════════════════════════════╗
║          WordPress Headless CMS — Dashboard          ║
║       WordPress + MariaDB + Redis + WP-Cron          ║
╚══════════════════════════════════════════════════════╝
B
	printf '%s' "$C_RST"
}

# ===========================================================================
# Trạng thái
# ===========================================================================
svc_dot() { # svc_dot <service> — chấm màu theo health/state
	local cid st
	cid="$(docker compose ps -q "$1" 2>/dev/null | head -1 || true)"
	if [[ -z "$cid" ]]; then printf '%s○%s' "$C_DIM" "$C_RST"; return; fi
	st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
	case "$st" in
		healthy|running)     printf '%s●%s' "$C_GRN" "$C_RST" ;;
		starting|restarting) printf '%s●%s' "$C_YLW" "$C_RST" ;;
		*)                   printf '%s●%s' "$C_RED" "$C_RST" ;;
	esac
}

detect_project() { grep -m1 -oE 'project: .*' .env 2>/dev/null | cut -d' ' -f2- || true; }
detect_port()    { grep -m1 -oE '127\.0\.0\.1:[0-9]+' docker-compose.yml 2>/dev/null | cut -d: -f2 || true; }
env_get()        { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }

panel() {
	if [[ ! -f .env || ! -f docker-compose.yml ]]; then
		printf ' %sChưa có cấu hình — chọn 1) Cài đặt mới để bắt đầu.%s\n\n' "$C_YLW" "$C_RST"
		return
	fi
	local proj port url
	proj="$(detect_project)"; port="$(detect_port)"; url="$(env_get WP_SITE_URL)"
	printf ' %sProject%s : %-22s %sURL%s: %s\n' "$C_DIM" "$C_RST" "${proj:-?}" "$C_DIM" "$C_RST" "${url:-http://127.0.0.1:${port:-9000}}"
	printf ' %sLocal%s   : http://127.0.0.1:%-8s %sCORS%s: %s\n' "$C_DIM" "$C_RST" "${port:-9000}" "$C_DIM" "$C_RST" "$(env_get FRONTEND_ORIGIN)"
	printf ' %sServices%s: %s wordpress  %s db  %s redis  %s wpcron\n\n' "$C_DIM" "$C_RST" \
		"$(svc_dot wordpress)" "$(svc_dot db)" "$(svc_dot redis)" "$(svc_dot wpcron)"
}

# ===========================================================================
# Wizard — cài đặt mới
# ===========================================================================

# Mặc định cho cấu hình nâng cao (giữ nguyên = giá trị production hiện tại)
WP_IMAGE_DEFAULT="wordpress:7.0-php8.3-apache"
UPLOAD_LIMIT_DEFAULT="512M"
MEMORY_LIMIT_DEFAULT="512M"
PHP_TZ_DEFAULT="Asia/Ho_Chi_Minh"
REDIS_MAXMEM_DEFAULT="256mb"
CRON_INTERVAL_DEFAULT="300"
WWW_DEFAULT="y"

wizard() {
	step 1 5 "Thông tin cơ bản"

	ask PROJECT "Tên project (vd: food-inno)" ""
	PROJECT="$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')"
	if [[ -z "$PROJECT" ]]; then
		err "Tên project không hợp lệ."
		return 1
	fi
	SLUG="$(printf '%s' "$PROJECT" | tr '-' '_' | tr -cd 'a-z0-9_')"

	ask DOMAIN "Domain CMS (vd: cms.domain.com.vn, trống = chỉ local)" ""
	DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')"

	ask HOST_PORT "Cổng host expose WordPress" "9000"

	local default_site_url
	if [[ -n "$DOMAIN" ]]; then default_site_url="https://${DOMAIN}"; else default_site_url="http://127.0.0.1:${HOST_PORT}"; fi
	ask SITE_URL "WP_SITE_URL (URL công khai của CMS)" "$default_site_url"
	ask FRONTEND "FRONTEND_ORIGIN cho CORS (nhiều origin: phẩy)" "http://localhost:3000"

	# Giá trị dẫn xuất + mặc định nâng cao
	WP_NAME="$PROJECT"
	DB_CONTAINER="${PROJECT}-db"
	REDIS_CONTAINER="${PROJECT}-redis"
	NETWORK="${PROJECT}-network"
	DB_NAME="${SLUG}_db"
	DB_USER="${SLUG}_user"
	PREFIX="${SLUG}_"
	WP_IMAGE="$WP_IMAGE_DEFAULT"
	UPLOAD_LIMIT="$UPLOAD_LIMIT_DEFAULT"
	MEMORY_LIMIT="$MEMORY_LIMIT_DEFAULT"
	PHP_TZ="$PHP_TZ_DEFAULT"
	REDIS_MAXMEM="$REDIS_MAXMEM_DEFAULT"
	CRON_INTERVAL="$CRON_INTERVAL_DEFAULT"
	WWW="$WWW_DEFAULT"
	ADVANCED=0

	step 2 5 "Cấu hình nâng cao (Enter = giữ mặc định)"
	if confirm "Tuỳ chỉnh nâng cao?"; then
		ADVANCED=1
		ask WP_IMAGE      "WordPress image" "$WP_IMAGE"
		ask UPLOAD_LIMIT  "Upload limit (PHP + nginx)" "$UPLOAD_LIMIT"
		ask MEMORY_LIMIT  "PHP memory_limit" "$MEMORY_LIMIT"
		ask PHP_TZ        "PHP timezone" "$PHP_TZ"
		ask REDIS_MAXMEM  "Redis maxmemory (object cache)" "$REDIS_MAXMEM"
		ask PREFIX        "Table prefix" "$PREFIX"
		ask CRON_INTERVAL "WP-Cron interval (giây)" "$CRON_INTERVAL"
		ask WWW           "Nginx/SSL kèm www.${DOMAIN:-<domain>}? (y/n)" "$WWW"
	else
		info "Dùng toàn bộ giá trị mặc định."
	fi

	step 3 5 "Xem lại"
	printf '%s┌────────────────────────────────────────────────────────────┐%s\n' "$C_DIM" "$C_RST"
	printf '  %-16s: %s\n' \
		"Project"        "$PROJECT" \
		"Domain"         "${DOMAIN:-(local — bỏ qua nginx/certbot)}" \
		"Containers"     "$WP_NAME, $DB_CONTAINER, $REDIS_CONTAINER, ${WP_NAME}-wpcron" \
		"Network"        "$NETWORK" \
		"Host port"      "127.0.0.1:$HOST_PORT → :80" \
		"DB / user"      "$DB_NAME / $DB_USER" \
		"Table prefix"   "$PREFIX" \
		"WP_SITE_URL"    "$SITE_URL" \
		"FRONTEND_ORIGIN" "$FRONTEND" \
		"Image"          "$WP_IMAGE" \
		"Upload / Memory" "$UPLOAD_LIMIT / $MEMORY_LIMIT" \
		"Redis maxmem"   "$REDIS_MAXMEM" \
		"Cron interval"  "${CRON_INTERVAL}s" \
		"Timezone"       "$PHP_TZ"
	printf '%s└────────────────────────────────────────────────────────────┘%s\n' "$C_DIM" "$C_RST"

	if ! confirm "Tiếp tục sinh file?"; then
		err "Đã huỷ."
		return 1
	fi

	step 4 5 "Sinh file cấu hình"
	write_env
	write_compose
	if [[ "$ADVANCED" == "1" ]]; then
		write_php_ini
	fi
	if [[ -n "$DOMAIN" ]]; then
		render_nginx "$DOMAIN" "$HOST_PORT" "$UPLOAD_LIMIT" "$WWW"
	fi

	step 5 5 "Nginx + SSL"
	if [[ -n "$DOMAIN" ]]; then
		install_nginx "$DOMAIN" "$WWW"
	else
		info "Không có domain — bỏ qua nginx/certbot."
	fi

	echo
	ok "Hoàn tất. Tiếp theo:"
	echo "  1. docker-compose up -d        (hoặc menu 5)"
	echo "  2. ./wp-init.sh                (hoặc menu 2 — tự cài WP + permalink + plugins)"
}

write_env() {
	if [[ -f .env ]]; then
		err "CẢNH BÁO: .env đã tồn tại."
		err "Tạo mới = mật khẩu DB mới. Nếu mysql-data/ đã khởi tạo, MariaDB sẽ KHÔNG"
		err "nhận mật khẩu mới → login thất bại. Chỉ ghi đè khi chưa 'up' lần nào."
		if ! confirm "Ghi đè .env?"; then
			info "Giữ nguyên .env hiện tại."
			return 0
		fi
	fi

	cat > .env <<ENV
# Sinh bởi setup.sh — project: $PROJECT
# WordPress Database Configuration
MYSQL_ROOT_PASSWORD=$(rand 28)
MYSQL_DATABASE=$DB_NAME
MYSQL_USER=$DB_USER
MYSQL_PASSWORD=$(rand 24)

# WordPress Table Prefix
WORDPRESS_TABLE_PREFIX=$PREFIX

# WordPress salts/keys (sinh ngẫu nhiên — đổi sẽ invalidate mọi session đang đăng nhập)
WORDPRESS_AUTH_KEY=$(rand 64)
WORDPRESS_SECURE_AUTH_KEY=$(rand 64)
WORDPRESS_LOGGED_IN_KEY=$(rand 64)
WORDPRESS_NONCE_KEY=$(rand 64)
WORDPRESS_AUTH_SALT=$(rand 64)
WORDPRESS_SECURE_AUTH_SALT=$(rand 64)
WORDPRESS_LOGGED_IN_SALT=$(rand 64)
WORDPRESS_NONCE_SALT=$(rand 64)

# Headless CMS
WP_SITE_URL=$SITE_URL
FRONTEND_ORIGIN=$FRONTEND
ENV
	# Guard: random generator fail sẽ tạo giá trị rỗng (password/salt) — chặn ngay
	if grep -qE '^[A-Z_]+=$' .env; then
		err "Lỗi: .env có giá trị rỗng (không sinh được chuỗi ngẫu nhiên?). Kiểm tra /dev/urandom."
		exit 1
	fi
	ok "Đã ghi .env"
}

write_compose() {
	if [[ -f docker-compose.yml ]] && ! confirm "Ghi đè docker-compose.yml?"; then
		err "Bỏ qua docker-compose.yml."
		return 0
	fi
	# Heredoc trích dẫn ('TEMPLATE') giữ nguyên ${...} và $$ cho Docker/PHP;
	# sed thay các placeholder %%...%% bằng giá trị project.
	cat <<'TEMPLATE' | sed \
		-e "s|%%WP_IMAGE%%|${WP_IMAGE}|g" \
		-e "s|%%WP_NAME%%|${WP_NAME}|g" \
		-e "s|%%DB_CONTAINER%%|${DB_CONTAINER}|g" \
		-e "s|%%REDIS_CONTAINER%%|${REDIS_CONTAINER}|g" \
		-e "s|%%NETWORK%%|${NETWORK}|g" \
		-e "s|%%HOST_PORT%%|${HOST_PORT}|g" \
		-e "s|%%REDIS_MAXMEM%%|${REDIS_MAXMEM}|g" \
		-e "s|%%CRON_INTERVAL%%|${CRON_INTERVAL}|g" \
		> docker-compose.yml
# Tham khảo image chính thức: https://hub.docker.com/_/wordpress
services:
  wordpress:
    # PHP 8.3 là default của image chính thức; pin minor để patch release tự cập nhật
    image: %%WP_IMAGE%%
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
      WORDPRESS_DEBUG: ${WORDPRESS_DEBUG:-}
      # Salts/keys cố định qua .env (sinh bởi setup.sh) — session không bị
      # invalidate khi recreate container. :? bắt buộc có, tránh salt rỗng.
      WORDPRESS_AUTH_KEY: ${WORDPRESS_AUTH_KEY:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_SECURE_AUTH_KEY: ${WORDPRESS_SECURE_AUTH_KEY:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_LOGGED_IN_KEY: ${WORDPRESS_LOGGED_IN_KEY:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_NONCE_KEY: ${WORDPRESS_NONCE_KEY:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_AUTH_SALT: ${WORDPRESS_AUTH_SALT:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_SECURE_AUTH_SALT: ${WORDPRESS_SECURE_AUTH_SALT:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_LOGGED_IN_SALT: ${WORDPRESS_LOGGED_IN_SALT:?thiếu salt — chạy ./setup.sh}
      WORDPRESS_NONCE_SALT: ${WORDPRESS_NONCE_SALT:?thiếu salt — chạy ./setup.sh}
      WP_SITE_URL: ${WP_SITE_URL:-}
      FRONTEND_ORIGIN: ${FRONTEND_ORIGIN:-}
      WORDPRESS_CONFIG_EXTRA: |
        /* Redis object cache (plugin Redis Object Cache đọc các hằng này) */
        define('WP_REDIS_HOST', 'redis');
        define('WP_REDIS_PORT', 6379);
        define('WP_REDIS_DATABASE', 0);
        define('WP_REDIS_TIMEOUT', 1);
        define('WP_REDIS_READ_TIMEOUT', 1);
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
        /* WP-Cron tách khỏi request người dùng — service wpcron gọi định kỳ */
        define('DISABLE_WP_CRON', true);
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

  wpcron:
    image: alpine:3.21
    container_name: %%WP_NAME%%-wpcron
    restart: unless-stopped
    # WP-Cron đã tắt khỏi request người dùng (DISABLE_WP_CRON) — sidecar này
    # gọi wp-cron.php định kỳ để scheduled posts/cron jobs chạy đúng giờ
    command: /bin/sh -c 'while true; do wget -q -T 30 -O /dev/null "http://wordpress/wp-cron.php?doing_wp_cron" 2>/dev/null || true; sleep %%CRON_INTERVAL%%; done'
    depends_on:
      wordpress:
        condition: service_healthy
    networks:
      - %%NETWORK%%

  redis:
    image: redis:7-alpine
    container_name: %%REDIS_CONTAINER%%
    restart: unless-stopped
    # Object cache là ephemeral: bỏ AOF, giới hạn RAM và evict LRU thay vì phình/OOM
    command: redis-server --maxmemory %%REDIS_MAXMEM%% --maxmemory-policy allkeys-lru --save "" --appendonly no
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
}

write_php_ini() { # dùng UPLOAD_LIMIT / MEMORY_LIMIT / PHP_TZ
	if ! confirm "Ghi đè php-uploads.ini (upload=$UPLOAD_LIMIT, memory=$MEMORY_LIMIT, tz=$PHP_TZ)?"; then
		info "Giữ nguyên php-uploads.ini."
		return 0
	fi
	cat > php-uploads.ini <<INI
[PHP]
; Sinh bởi setup.sh — restart container wordpress để áp dụng

; File Uploads
file_uploads = On
upload_max_filesize = $UPLOAD_LIMIT
max_file_uploads = 20

; Resource Limits
memory_limit = $MEMORY_LIMIT
post_max_size = $UPLOAD_LIMIT
max_execution_time = 600
max_input_time = 300
max_input_vars = 3000

; Timezone
date.timezone = $PHP_TZ

; Error handling
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 1024
ignore_repeated_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

; Performance
realpath_cache_size = 4096k
realpath_cache_ttl = 600
opcache.memory_consumption = 256
opcache.max_accelerated_files = 7963
opcache.revalidate_freq = 0
opcache.enable_cli = 1
opcache.enable = 1
INI
	ok "Đã ghi php-uploads.ini"
}

# ===========================================================================
# Nginx + SSL
# ===========================================================================
render_nginx() { # render_nginx <domain> <port> <client_max_body> <www y/n>
	local domain="$1" port="$2" body="$3" www="$4" server_names conf
	conf="${domain}.conf"
	if [[ "$www" == "y" ]]; then server_names="$domain www.$domain"; else server_names="$domain"; fi

	if [[ -f "$conf" ]] && ! confirm "Ghi đè ${conf}?"; then
		err "Bỏ qua ${conf}."
		return 0
	fi
	# Chỉ block :80 — certbot --nginx sẽ tự thêm block 443 + redirect khi chạy.
	cat <<NGINX | sed \
		-e "s|%%SERVER_NAMES%%|${server_names}|g" \
		-e "s|%%DOMAIN%%|${domain}|g" \
		-e "s|%%HOST_PORT%%|${port}|g" \
		-e "s|%%CLIENT_MAX_BODY%%|${body}|g" \
		> "$conf"
server {
    listen 80;
    server_name %%SERVER_NAMES%%;

    # Increase upload size for WordPress
    client_max_body_size %%CLIENT_MAX_BODY%%;

    # Logging
    access_log /var/log/nginx/%%DOMAIN%%-access.log;
    error_log /var/log/nginx/%%DOMAIN%%-error.log;

    # Timeout settings
    proxy_connect_timeout 180s;
    proxy_send_timeout 180s;
    proxy_read_timeout 180s;

    # Reverse proxy all requests to WordPress container
    location / {
        proxy_pass http://127.0.0.1:%%HOST_PORT%%;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        # Buffering settings
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # Static files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|webp)\$ {
        proxy_pass http://127.0.0.1:%%HOST_PORT%%;
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
NGINX
	ok "Đã ghi ${conf}"
}

install_nginx() { # install_nginx <domain> <www y/n> — cài conf + certbot trên VPS
	# Tách local: set -u + expand trong cùng câu lệnh local làm ${domain} unbound
	local domain="$1" www="$2"
	local conf="${domain}.conf" certd
	certd="-d $domain"
	[[ "$www" == "y" ]] && certd="$certd -d www.$domain"

	[[ -f "$conf" ]] || { err "Không thấy $conf — render trước (wizard hoặc menu 3)."; return 1; }

	if [[ ! -d /etc/nginx/sites-available ]]; then
		info "Không thấy /etc/nginx/sites-available (chạy local?). Khi deploy lên VPS:"
		echo "  sudo cp $conf /etc/nginx/sites-available/"
		echo "  sudo ln -s /etc/nginx/sites-available/$conf /etc/nginx/sites-enabled/"
		echo "  sudo nginx -t && sudo systemctl reload nginx"
		echo "  sudo certbot --nginx $certd"
		return 0
	fi

	if ! confirm "Cài ${conf} vào nginx (sites-available + symlink) và reload?"; then
		return 0
	fi
	local SUDO=""
	[[ "$(id -u)" != "0" ]] && SUDO="sudo"
	$SUDO cp "$conf" "/etc/nginx/sites-available/${conf}"
	$SUDO ln -sf "/etc/nginx/sites-available/${conf}" "/etc/nginx/sites-enabled/${conf}"
	if $SUDO nginx -t; then
		$SUDO systemctl reload nginx
		ok "nginx đã reload với ${conf}"
	else
		err "nginx -t thất bại — đã KHÔNG reload. Kiểm tra config rồi reload thủ công."
		err "Gỡ symlink nếu cần: $SUDO rm /etc/nginx/sites-enabled/${conf}"
		return 1
	fi

	if command -v certbot >/dev/null 2>&1; then
		if confirm "Chạy certbot cấp SSL cho ${domain}?"; then
			# certbot --nginx tự thêm block 443 + redirect vào conf
			# shellcheck disable=SC2086
			$SUDO certbot --nginx $certd || {
				err "certbot thất bại (DNS chưa trỏ về server? port 80 chưa mở?)."
				err "Chạy lại sau: $SUDO certbot --nginx $certd"
			}
		fi
	else
		info "Không tìm thấy certbot. Cài rồi chạy:"
		echo "  sudo apt install certbot python3-certbot-nginx"
		echo "  sudo certbot --nginx $certd"
	fi
}

nginx_menu() { # chạy lại nginx/SSL độc lập (đổi domain, cấp lại SSL)
	local existing domain port www
	existing="$(ls -1 ./*.conf 2>/dev/null | head -1 | sed 's|^\./||; s|\.conf$||' || true)"
	ask domain "Domain" "$existing"
	[[ -z "$domain" ]] && { err "Cần domain."; return 1; }
	port="$(detect_port)"
	ask port "Cổng host của WordPress" "${port:-9000}"
	ask www "Kèm www.${domain}? (y/n)" "y"
	render_nginx "$domain" "$port" "$UPLOAD_LIMIT_DEFAULT" "$www"
	install_nginx "$domain" "$www"
}

# ===========================================================================
# Vận hành
# ===========================================================================
require_config() {
	if [[ ! -f docker-compose.yml || ! -f .env ]]; then
		err "Chưa có cấu hình — chạy wizard trước (menu 1)."
		return 1
	fi
}

do_up()      { require_config && { docker compose up -d; docker compose ps; }; }
do_down()    { require_config && docker compose down; }
do_restart() { require_config && { docker compose restart; docker compose ps; }; }

do_update() {
	require_config || return 1
	err "Nên backup trước khi update (menu b)."
	confirm "Tiếp tục pull image mới + up -d?" || return 0
	docker compose pull
	docker compose up -d
	docker compose ps
}

do_logs() {
	require_config || return 1
	local svc=""
	ask svc "Service (wordpress/db/redis/wpcron, trống = tất cả)" ""
	if confirm "Follow logs? (Ctrl-C để quay lại menu)"; then
		trap ' ' INT
		# shellcheck disable=SC2086
		docker compose logs -f --tail=100 $svc || true
		trap - INT
		echo
	else
		# shellcheck disable=SC2086
		docker compose logs --tail=100 $svc || true
	fi
}

do_status() {
	require_config || return 1
	info "Containers:"
	docker compose ps
	echo
	info "Tài nguyên:"
	local ids
	ids="$(docker compose ps -q 2>/dev/null || true)"
	if [[ -n "$ids" ]]; then
		# shellcheck disable=SC2086
		docker stats --no-stream $ids 2>/dev/null || true
	else
		echo "  (stack chưa chạy)"
	fi
	echo
	info "Redis object cache:"
	docker compose exec -T redis redis-cli info memory 2>/dev/null | grep -E 'used_memory_human|maxmemory_human|maxmemory_policy' || echo "  (redis chưa chạy)"
	docker compose exec -T redis redis-cli dbsize 2>/dev/null | sed 's/^/  keys: /' || true
	echo
	info "Dung lượng dữ liệu:"
	du -sh mysql-data public_html/wp-content/uploads backups 2>/dev/null | sed 's/^/  /' || true
}

# ===========================================================================
# Dữ liệu / công cụ
# ===========================================================================
do_backup_menu() {
	require_config || return 1
	if confirm "Kèm uploads (wp-content/uploads)?"; then
		./backup.sh --uploads
	else
		./backup.sh
	fi
}

do_restore() {
	require_config || return 1
	local files file n choice up
	files="$(ls -1t backups/db-*.sql.gz 2>/dev/null || true)"
	if [[ -z "$files" ]]; then
		err "Chưa có backup nào trong ./backups/ — chạy backup trước (menu b)."
		return 1
	fi
	info "Các bản backup DB (mới nhất trước):"
	echo "$files" | nl -w3 -s') '
	ask choice "Chọn số bản cần restore" ""
	file="$(echo "$files" | sed -n "${choice}p" 2>/dev/null || true)"
	[[ -n "$file" && -f "$file" ]] || { err "Lựa chọn không hợp lệ."; return 1; }

	err "SẼ GHI ĐÈ TOÀN BỘ database hiện tại bằng: $file"
	printf '%sGõ "yes" để xác nhận%s: ' "$C_RED" "$C_RST"
	read -r n || true
	[[ "$n" == "yes" ]] || { info "Đã huỷ."; return 0; }

	gunzip -c "$file" | docker compose exec -T db sh -c \
		'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
	ok "Đã restore DB từ $file"

	# Cache cũ lệch với DB vừa restore — xoá
	docker compose exec -T redis redis-cli flushall >/dev/null 2>&1 || true
	info "Đã flush Redis cache."

	up="$(ls -1t backups/uploads-*.tar.gz 2>/dev/null | head -1 || true)"
	if [[ -n "$up" ]] && confirm "Restore uploads từ $(basename "$up")?"; then
		tar -xzf "$up" -C public_html/wp-content/
		ok "Đã restore uploads."
	fi
}

# WP-CLI: phar tải on-demand vào /tmp trong container (ephemeral — recreate là
# mất nhưng tự tải lại; không đặt trong webroot để tránh lộ). Cùng cơ chế wp-init.sh.
wpexec() { docker compose exec -T -e HOME=/tmp -u www-data wordpress "$@" </dev/null; }
wpcli()  { wpexec php -d memory_limit=512M /tmp/wp-cli.phar --path=/var/www/html "$@"; }

ensure_wpcli() {
	if ! wpexec test -f /tmp/wp-cli.phar 2>/dev/null; then
		info "Tải WP-CLI vào container..."
		wpexec php -r "copy('https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar', '/tmp/wp-cli.phar');"
	fi
}

do_wpcli() {
	require_config || return 1
	if [[ -z "$(docker compose ps -q wordpress 2>/dev/null)" ]]; then
		err "Container wordpress chưa chạy (menu 5 để khởi động)."
		return 1
	fi
	ensure_wpcli
	info "Nhập lệnh wp (Enter rỗng để quay lại). Vd: plugin list | cache flush | user list"
	local CMD
	while true; do
		printf '%swp>%s ' "$C_CYN" "$C_RST"
		read -r CMD || break
		[[ -z "$CMD" ]] && break
		# shellcheck disable=SC2086
		wpcli $CMD || true
	done
}

# ===========================================================================
# Sửa cấu hình
# ===========================================================================
do_cors() { # Sửa nhanh FRONTEND_ORIGIN — shortcut của do_config option 1
	if [[ ! -f .env ]]; then
		err "Chưa có .env — chạy wizard trước (menu 1)."
		return 1
	fi
	local v cur
	cur="$(env_get FRONTEND_ORIGIN)"
	info "FRONTEND_ORIGIN hiện tại: ${cur:-(trống)}"
	ask v "FRONTEND_ORIGIN mới (nhiều origin: phẩy)" "$cur"
	if [[ "$v" == "$cur" ]]; then
		info "Không thay đổi."
		return 0
	fi
	sed -i.bak "s#^FRONTEND_ORIGIN=.*#FRONTEND_ORIGIN=$v#" .env && rm -f .env.bak
	ok "Đã cập nhật FRONTEND_ORIGIN = $v"
	if [[ -n "$(docker compose ps -q wordpress 2>/dev/null)" ]] && confirm "Up -d lại để áp dụng ngay?"; then
		docker compose up -d || true
	else
		info "Chạy 'up -d' (menu 5) để áp dụng."
	fi
}

do_config() {
	if [[ ! -f .env ]]; then
		err "Chưa có .env — chạy wizard trước (menu 1)."
		return 1
	fi
	echo "  1) Đổi FRONTEND_ORIGIN (CORS)"
	echo "  2) Đổi WP_SITE_URL"
	echo "  3) Mở .env bằng editor"
	echo "  4) PHP upload limit / memory / timezone"
	echo "  0) Quay lại"
	local c v cur
	ask c "Chọn" "0"
	case "$c" in
		1)
			cur="$(env_get FRONTEND_ORIGIN)"
			ask v "FRONTEND_ORIGIN mới (nhiều origin: phẩy)" "$cur"
			sed -i.bak "s#^FRONTEND_ORIGIN=.*#FRONTEND_ORIGIN=$v#" .env && rm -f .env.bak
			ok "Đã cập nhật FRONTEND_ORIGIN. Chạy 'up -d' (menu 5) để áp dụng."
			;;
		2)
			cur="$(env_get WP_SITE_URL)"
			ask v "WP_SITE_URL mới" "$cur"
			sed -i.bak "s#^WP_SITE_URL=.*#WP_SITE_URL=$v#" .env && rm -f .env.bak
			ok "Đã cập nhật WP_SITE_URL. Chạy 'up -d' (menu 5) để áp dụng."
			;;
		3)
			"${EDITOR:-vi}" .env
			;;
		4)
			ask UPLOAD_LIMIT "Upload limit (PHP)" "$UPLOAD_LIMIT_DEFAULT"
			ask MEMORY_LIMIT "PHP memory_limit" "$MEMORY_LIMIT_DEFAULT"
			ask PHP_TZ       "PHP timezone" "$PHP_TZ_DEFAULT"
			write_php_ini
			info "Lưu ý: nginx client_max_body_size cần đổi tay nếu khác (file <domain>.conf)."
			if confirm "Restart container wordpress để áp dụng?"; then
				docker compose restart wordpress || true
			fi
			;;
	esac
}

# ===========================================================================
# Dashboard
# ===========================================================================
menu_text() {
	printf '%s ── Cài đặt ──────────────────%s        %s── Vận hành ─────────────────%s\n' "$C_DIM" "$C_RST" "$C_DIM" "$C_RST"
	echo "  1) Cài đặt mới (wizard)              5) Khởi động (up -d)"
	echo "  2) Cài WordPress + plugins           6) Dừng (down)"
	echo "  3) Nginx + SSL (certbot)             7) Restart"
	echo "  4) Sửa cấu hình                      8) Logs"
	echo "                                       9) Cập nhật images"
	printf '%s ── Dữ liệu / Công cụ ────────────────────────────────────────────%s\n' "$C_DIM" "$C_RST"
	echo "  b) Backup   r) Restore   w) WP-CLI   c) Sửa CORS   s) Trạng thái   0) Thoát"
	echo
}

dashboard() {
	local choice
	while true; do
		[[ -t 1 ]] && clear
		banner
		panel
		menu_text
		printf '%sChọn%s: ' "$C_CYN" "$C_RST"
		read -r choice || exit 0
		echo
		case "$choice" in
			1) wizard || true; pause ;;
			2) ./wp-init.sh || true; pause ;;
			3) nginx_menu || true; pause ;;
			4) do_config || true; pause ;;
			5) do_up || true; pause ;;
			6) do_down || true; pause ;;
			7) do_restart || true; pause ;;
			8) do_logs || true; pause ;;
			9) do_update || true; pause ;;
			b|B) do_backup_menu || true; pause ;;
			r|R) do_restore || true; pause ;;
			w|W) do_wpcli || true; pause ;;
			c|C) do_cors || true; pause ;;
			s|S) do_status || true; pause ;;
			0|q|Q) exit 0 ;;
			*) err "Lựa chọn không hợp lệ."; pause ;;
		esac
	done
}

usage() {
	cat <<USAGE
Cách dùng:
  ./setup.sh            # mở dashboard
  ./setup.sh wizard     # wizard cài đặt mới
  ./setup.sh up         # docker compose up -d
  ./setup.sh down       # docker compose down
  ./setup.sh restart    # docker compose restart
  ./setup.sh status     # trạng thái chi tiết
  ./setup.sh backup     # backup DB (thêm --uploads nếu cần)
  ./setup.sh init       # cài WordPress + plugins (wp-init.sh)
  ./setup.sh nginx      # render + cài nginx/SSL
USAGE
}

# ===========================================================================
# Main
# ===========================================================================
case "${1:-}" in
	"")        dashboard ;;
	wizard)    wizard ;;
	up)        do_up ;;
	down)      do_down ;;
	restart)   do_restart ;;
	status)    do_status ;;
	backup)    shift; ./backup.sh "$@" ;;
	init)      ./wp-init.sh ;;
	nginx)     nginx_menu ;;
	-h|--help|help) usage ;;
	*)         err "Lệnh không hợp lệ: $1"; usage; exit 1 ;;
esac
