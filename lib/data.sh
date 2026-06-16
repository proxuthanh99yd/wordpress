# shellcheck shell=bash
# lib/data.sh — nạp bởi setup.sh (source). Không chạy độc lập.

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

# Đảm bảo đủ điều kiện chạy wp-cli: có config + container wordpress chạy + phar sẵn sàng
require_wp() {
	require_config || return 1
	if [[ -z "$(docker compose ps -q wordpress 2>/dev/null)" ]]; then
		err "Container wordpress chưa chạy (menu 5 để khởi động)."
		return 1
	fi
	ensure_wpcli
}

do_wpcli() {
	require_wp || return 1
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

