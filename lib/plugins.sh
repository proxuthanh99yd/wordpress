# shellcheck shell=bash
# lib/plugins.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Quản lý plugin (qua WP-CLI trong container)
# ===========================================================================
do_plugins() {
	require_wp || return 1
	local c slug term
	while true; do
		echo
		printf '%s── Quản lý plugin ──────────────────────────%s\n' "$C_DIM" "$C_RST"
		echo "  1) Danh sách đã cài (list)"
		echo "  2) Tìm trên wordpress.org (search)"
		echo "  3) Cài đặt (install [+ kích hoạt])"
		echo "  4) Kích hoạt (activate)"
		echo "  5) Vô hiệu hoá (deactivate)"
		echo "  6) Gỡ bỏ (delete)"
		echo "  7) Cập nhật (update)"
		echo "  0) Quay lại"
		ask c "Chọn" "0"
		case "$c" in
			1)
				wpcli plugin list || true
				;;
			2)
				ask term "Từ khoá tìm" ""
				[[ -z "$term" ]] && { info "Bỏ qua."; continue; }
				wpcli plugin search "$term" --fields=name,slug,rating,num_ratings --per-page=20 || true
				;;
			3)
				ask slug "Slug plugin cần cài (vd: wordpress-seo)" ""
				[[ -z "$slug" ]] && { info "Bỏ qua."; continue; }
				if confirm "Kích hoạt luôn sau khi cài?"; then
					wpcli plugin install "$slug" --activate || true
				else
					wpcli plugin install "$slug" || true
				fi
				;;
			4)
				ask slug "Slug plugin cần kích hoạt" ""
				[[ -z "$slug" ]] && { info "Bỏ qua."; continue; }
				wpcli plugin activate "$slug" || true
				;;
			5)
				ask slug "Slug plugin cần vô hiệu hoá" ""
				[[ -z "$slug" ]] && { info "Bỏ qua."; continue; }
				wpcli plugin deactivate "$slug" || true
				;;
			6)
				ask slug "Slug plugin cần gỡ bỏ" ""
				[[ -z "$slug" ]] && { info "Bỏ qua."; continue; }
				confirm "Gỡ bỏ '$slug'? (xoá file plugin, không hoàn tác được)" || continue
				# delete yêu cầu plugin đã tắt; tắt trước cho chắc (bỏ qua nếu vốn đã tắt)
				wpcli plugin deactivate "$slug" 2>/dev/null || true
				wpcli plugin delete "$slug" || true
				;;
			7)
				ask slug "Slug cần cập nhật (trống = tất cả)" ""
				if [[ -z "$slug" ]]; then
					wpcli plugin update --all || true
				else
					wpcli plugin update "$slug" || true
				fi
				;;
			0|"") return 0 ;;
			*) err "Lựa chọn không hợp lệ." ;;
		esac
	done
}
