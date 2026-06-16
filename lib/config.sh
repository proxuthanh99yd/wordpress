# shellcheck shell=bash
# lib/config.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Sửa cấu hình
# ===========================================================================
# Sửa 1 biến trong .env (biến env → cần up -d recreate container, không phải restart).
set_env_var() { # set_env_var KEY "câu hỏi"
	local key="$1" q="$2" v cur
	if [[ ! -f .env ]]; then
		err "Chưa có .env — chạy wizard trước (menu 1)."
		return 1
	fi
	cur="$(env_get "$key")"
	info "$key hiện tại: ${cur:-(trống)}"
	ask v "$q" "$cur"
	if [[ "$v" == "$cur" ]]; then
		info "Không thay đổi."
		return 0
	fi
	sed -i.bak "s#^${key}=.*#${key}=$v#" .env && rm -f .env.bak
	ok "Đã cập nhật $key = $v"
	if [[ -n "$(docker compose ps -q wordpress 2>/dev/null)" ]] && confirm "Up -d lại để áp dụng ngay?"; then
		docker compose up -d || true
	else
		info "Chạy 'up -d' (menu 5) để áp dụng."
	fi
}

# Shortcut sửa nhanh FRONTEND_ORIGIN từ dashboard (menu c)
do_cors() { set_env_var FRONTEND_ORIGIN "FRONTEND_ORIGIN mới (nhiều origin: phẩy)"; }

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
	local c
	ask c "Chọn" "0"
	case "$c" in
		1)
			set_env_var FRONTEND_ORIGIN "FRONTEND_ORIGIN mới (nhiều origin: phẩy)"
			;;
		2)
			set_env_var WP_SITE_URL "WP_SITE_URL mới"
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

