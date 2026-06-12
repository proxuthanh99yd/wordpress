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

read -rp "Domain của CMS (vd: cms.domain.com.vn, bỏ trống nếu chỉ chạy local): " DOMAIN
DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')"

read -rp "Cổng host expose WordPress [9000]: " HOST_PORT
HOST_PORT="${HOST_PORT:-9000}"

if [[ -n "$DOMAIN" ]]; then
	DEFAULT_SITE_URL="https://${DOMAIN}"
else
	DEFAULT_SITE_URL="http://127.0.0.1:${HOST_PORT}"
fi
read -rp "WP_SITE_URL (URL công khai của CMS) [${DEFAULT_SITE_URL}]: " SITE_URL
SITE_URL="${SITE_URL:-$DEFAULT_SITE_URL}"

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
  Domain           : ${DOMAIN:-"(local — bỏ qua nginx/certbot)"}
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
# Tham khảo image chính thức: https://hub.docker.com/_/wordpress
services:
  wordpress:
    # PHP 8.3 là default của image chính thức; pin minor để patch release tự cập nhật
    image: wordpress:7.0-php8.3-apache
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
    # gọi wp-cron.php mỗi 5 phút để scheduled posts/cron jobs chạy đúng giờ
    command: /bin/sh -c 'while true; do wget -q -T 30 -O /dev/null "http://wordpress/wp-cron.php?doing_wp_cron" 2>/dev/null || true; sleep 300; done'
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

# ---------------------------------------------------------------------------
# 4. Sinh nginx config <domain>.conf (chỉ khi có domain)
# ---------------------------------------------------------------------------
NGINX_CONF=""
if [[ -n "$DOMAIN" ]]; then
	NGINX_CONF="${DOMAIN}.conf"
	if [[ -f "$NGINX_CONF" ]] && ! confirm "Ghi đè ${NGINX_CONF}?"; then
		err "Bỏ qua ${NGINX_CONF}."
	else
		# Chỉ block :80 — certbot --nginx sẽ tự thêm block 443 + redirect khi chạy.
		cat <<NGINX | sed \
			-e "s|%%DOMAIN%%|${DOMAIN}|g" \
			-e "s|%%HOST_PORT%%|${HOST_PORT}|g" \
			> "$NGINX_CONF"
server {
    listen 80;
    server_name %%DOMAIN%% www.%%DOMAIN%%;

    # Increase upload size for WordPress
    client_max_body_size 512M;

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
		ok "Đã ghi ${NGINX_CONF}"
	fi
fi

# ---------------------------------------------------------------------------
# 5. Cài vào nginx (sites-available + symlink) và chạy certbot — chỉ trên VPS
# ---------------------------------------------------------------------------
if [[ -n "$DOMAIN" && -n "$NGINX_CONF" && -f "$NGINX_CONF" ]]; then
	if [[ -d /etc/nginx/sites-available ]]; then
		if confirm "Cài ${NGINX_CONF} vào nginx (sites-available + symlink) và reload?"; then
			SUDO=""
			[[ "$(id -u)" != "0" ]] && SUDO="sudo"
			$SUDO cp "$NGINX_CONF" "/etc/nginx/sites-available/${NGINX_CONF}"
			$SUDO ln -sf "/etc/nginx/sites-available/${NGINX_CONF}" "/etc/nginx/sites-enabled/${NGINX_CONF}"
			if $SUDO nginx -t; then
				$SUDO systemctl reload nginx
				ok "nginx đã reload với ${NGINX_CONF}"
			else
				err "nginx -t thất bại — đã KHÔNG reload. Kiểm tra config rồi reload thủ công."
				err "Gỡ symlink nếu cần: $SUDO rm /etc/nginx/sites-enabled/${NGINX_CONF}"
				exit 1
			fi

			if command -v certbot >/dev/null 2>&1; then
				if confirm "Chạy certbot cấp SSL cho ${DOMAIN} (+ www.${DOMAIN})?"; then
					# certbot --nginx tự thêm block 443 + redirect vào conf
					$SUDO certbot --nginx -d "$DOMAIN" -d "www.${DOMAIN}" || {
						err "certbot thất bại (DNS chưa trỏ về server? port 80 chưa mở?)."
						err "Chạy lại sau: $SUDO certbot --nginx -d $DOMAIN -d www.$DOMAIN"
					}
				fi
			else
				info "Không tìm thấy certbot. Cài rồi chạy:"
				echo "  sudo apt install certbot python3-certbot-nginx"
				echo "  sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN"
			fi
		fi
	else
		info "Không thấy /etc/nginx/sites-available (chạy local?). Khi deploy lên VPS:"
		echo "  sudo cp $NGINX_CONF /etc/nginx/sites-available/"
		echo "  sudo ln -s /etc/nginx/sites-available/$NGINX_CONF /etc/nginx/sites-enabled/"
		echo "  sudo nginx -t && sudo systemctl reload nginx"
		echo "  sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN"
	fi
fi

info ""
ok "Hoàn tất. Tiếp theo:"
echo "  1. docker-compose up -d"
echo "  2. ./wp-init.sh   # tự cài WordPress core + permalink + Redis Object Cache + WPGraphQL"
