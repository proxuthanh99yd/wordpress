# shellcheck shell=bash
# lib/plugins.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Quản lý plugin (qua WP-CLI trong container)
# ===========================================================================

# Decode vài HTML entity hay gặp trong tên plugin (search) về ASCII cho dễ đọc.
# Dùng cho cột cuối cùng nên có rút ngắn cũng không làm lệch các cột trước.
plugin_decode_entities() {
	sed -e 's/&amp;/\&/g; s/&#0*38;/\&/g' \
	    -e 's/&#8211;/-/g; s/&#8212;/-/g' \
	    -e "s/&#8217;/'/g; s/&#8216;/'/g; s/&#0*39;/'/g" \
	    -e 's/&#8220;/"/g; s/&#8221;/"/g; s/&quot;/"/g'
}

do_plugins() {
	require_wp || return 1
	local c slug term
	while true; do
		[[ -t 1 ]] && clear
		printf '%s── Quản lý plugin (WP-CLI) ──────────────────%s\n\n' "$C_BLD" "$C_RST"
		echo "  1) Danh sách đã cài          5) Vô hiệu hoá"
		echo "  2) Tìm trên wordpress.org    6) Gỡ bỏ"
		echo "  3) Cài đặt (+kích hoạt)      7) Cập nhật"
		echo "  4) Kích hoạt                 0) Quay lại"
		echo
		ask c "Chọn" "0"
		echo
		case "$c" in
			1)
				wpcli plugin list --fields=name,status,version,update --format=table || true
				;;
			2)
				ask term "Từ khoá tìm" ""
				[[ -z "$term" ]] && continue
				echo
				# slug đứng đầu (dễ copy đi cài), name để cuối (đã decode entity)
				wpcli plugin search "$term" --fields=slug,rating,name --per-page=10 --format=table \
					| plugin_decode_entities || true
				;;
			3)
				ask slug "Slug plugin cần cài (vd: wordpress-seo)" ""
				[[ -z "$slug" ]] && continue
				if confirm "Kích hoạt luôn sau khi cài?"; then
					wpcli plugin install "$slug" --activate || true
				else
					wpcli plugin install "$slug" || true
				fi
				;;
			4)
				ask slug "Slug plugin cần kích hoạt" ""
				[[ -z "$slug" ]] && continue
				wpcli plugin activate "$slug" || true
				;;
			5)
				ask slug "Slug plugin cần vô hiệu hoá" ""
				[[ -z "$slug" ]] && continue
				wpcli plugin deactivate "$slug" || true
				;;
			6)
				ask slug "Slug plugin cần gỡ bỏ" ""
				[[ -z "$slug" ]] && continue
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
		pause
	done
}
