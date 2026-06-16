# shellcheck shell=bash
# lib/wizard.sh — nạp bởi setup.sh (source). Không chạy độc lập.

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

