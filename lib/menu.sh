# shellcheck shell=bash
# lib/menu.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Dashboard
# ===========================================================================
# Nhãn cho menu gum (tiền tố "<mã>) " để tách lại mã bằng ${sel%%)*} → dùng chung case)
DASH_LABELS=(
	"1) Cài đặt mới (wizard)"
	"2) Cài WordPress + plugins"
	"3) Nginx + SSL (certbot)"
	"4) Sửa cấu hình"
	"5) Khởi động (up -d)"
	"6) Dừng (down)"
	"7) Restart"
	"8) Logs"
	"9) Cập nhật images"
	"b) Backup"
	"r) Restore"
	"w) WP-CLI"
	"p) Quản lý plugin"
	"c) Sửa CORS"
	"s) Trạng thái"
	"h) Health check (REST/GraphQL)"
	"0) Thoát"
)

menu_text() {
	printf '%s ── Cài đặt ──────────────────%s        %s── Vận hành ─────────────────%s\n' "$C_DIM" "$C_RST" "$C_DIM" "$C_RST"
	echo "  1) Cài đặt mới (wizard)              5) Khởi động (up -d)"
	echo "  2) Cài WordPress + plugins           6) Dừng (down)"
	echo "  3) Nginx + SSL (certbot)             7) Restart"
	echo "  4) Sửa cấu hình                      8) Logs"
	echo "                                       9) Cập nhật images"
	printf '%s ── Dữ liệu / Công cụ ────────────────────────────────────────────%s\n' "$C_DIM" "$C_RST"
	echo "  b) Backup   r) Restore   w) WP-CLI   p) Plugin   c) Sửa CORS"
	echo "  s) Trạng thái   h) Health check (REST/GraphQL)   0) Thoát"
	printf '%s  Mẹo: cài gum để menu chọn bằng phím ↑↓ → ./setup.sh ui%s\n' "$C_DIM" "$C_RST"
	echo
}

dashboard() {
	local choice sel
	while true; do
		[[ -t 1 ]] && clear
		banner
		panel
		if has_gum; then
			sel="$(ui_menu "Chọn thao tác" "${DASH_LABELS[@]}")"
			if [[ -z "$sel" ]]; then choice=""; else choice="${sel%%)*}"; fi
		else
			menu_text
			printf '%sChọn%s: ' "$C_CYN" "$C_RST"
			read -r choice || exit 0
		fi
		echo
		case "$choice" in
			"") continue ;;
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
			p|P) do_plugins || true; pause ;;
			c|C) do_cors || true; pause ;;
			s|S) do_status || true; pause ;;
			h|H) do_healthcheck || true; pause ;;
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
  ./setup.sh health     # kiểm tra endpoints REST/GraphQL
  ./setup.sh backup     # backup DB (thêm --uploads nếu cần)
  ./setup.sh init       # cài WordPress + plugins (wp-init.sh)
  ./setup.sh plugins    # quản lý plugin (list/search/cài/active/gỡ)
  ./setup.sh nginx      # render + cài nginx/SSL
  ./setup.sh ui         # cài gum để menu đẹp hơn (chọn bằng phím ↑↓)
USAGE
}

