# shellcheck shell=bash
# lib/nginx.sh — nạp bởi setup.sh (source). Không chạy độc lập.

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

# Cài certbot nếu chưa có (gói distro tự tạo certbot.timer auto-renew).
# Trả 0 nếu certbot sẵn sàng, 1 nếu không cài được / user từ chối.
ensure_certbot() {
	command -v certbot >/dev/null 2>&1 && return 0
	local SUDO=""
	[[ "$(id -u)" != "0" ]] && SUDO="sudo"
	info "Chưa có certbot."
	if command -v apt-get >/dev/null 2>&1; then
		confirm "Cài certbot + python3-certbot-nginx bằng apt?" || return 1
		$SUDO apt-get update -y && $SUDO apt-get install -y certbot python3-certbot-nginx
	elif command -v dnf >/dev/null 2>&1; then
		confirm "Cài certbot + python3-certbot-nginx bằng dnf?" || return 1
		$SUDO dnf install -y certbot python3-certbot-nginx
	elif command -v yum >/dev/null 2>&1; then
		confirm "Cài certbot + python3-certbot-nginx bằng yum?" || return 1
		$SUDO yum install -y certbot python3-certbot-nginx
	else
		err "Không nhận diện được trình quản lý gói (apt/dnf/yum)."
		echo "  Cài thủ công: certbot + python3-certbot-nginx (hoặc: sudo snap install --classic certbot)"
		return 1
	fi
	if command -v certbot >/dev/null 2>&1; then
		ok "Đã cài certbot."
		return 0
	fi
	err "Cài certbot thất bại."
	return 1
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

	if ! ensure_certbot; then
		info "Bỏ qua SSL. Sau khi có certbot, chạy: $SUDO certbot --nginx $certd"
		return 0
	fi
	if confirm "Chạy certbot cấp SSL cho ${domain}?"; then
		# certbot --nginx tự thêm block 443 + redirect vào conf
		# shellcheck disable=SC2086
		$SUDO certbot --nginx $certd || {
			err "certbot thất bại (DNS chưa trỏ về server? port 80 chưa mở?)."
			err "Chạy lại sau: $SUDO certbot --nginx $certd"
		}
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

