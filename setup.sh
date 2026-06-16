#!/usr/bin/env bash
#
# setup.sh — Dashboard quản lý WordPress Headless CMS.
#
#   ./setup.sh            # mở dashboard (menu tương tác)
#   ./setup.sh wizard     # chạy thẳng wizard cài đặt mới
#   ./setup.sh up|down|restart|status|health|backup|init|plugins|nginx|ui
#                         # chạy thẳng 1 tác vụ, không vào menu
#
# Kiến trúc: wp-init.sh (cài WP + plugins) và backup.sh (dump DB/uploads)
# vẫn là script standalone — dashboard chỉ gọi lại chúng.

set -euo pipefail

cd "$(dirname "$0")"

# ── Nạp các module trong lib/ (chỉ định nghĩa hàm + biến mặc định, không chạy gì) ──
for _m in ui status wizard nginx ops health data plugins config menu; do
	source "lib/${_m}.sh"
done
unset _m

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
	health)    do_healthcheck ;;
	backup)    shift; ./backup.sh "$@" ;;
	init)      ./wp-init.sh ;;
	plugins)   do_plugins ;;
	nginx)     nginx_menu ;;
	ui)        ensure_gum ;;
	-h|--help|help) usage ;;
	*)         err "Lệnh không hợp lệ: $1"; usage; exit 1 ;;
esac
