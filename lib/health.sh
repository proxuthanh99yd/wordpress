# shellcheck shell=bash
# lib/health.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Health check — endpoints headless (REST API / WPGraphQL)
# ===========================================================================
check_url() { # check_url <nhãn> <url> [curl args...] — in HTTP status có màu
	local label="$1" url="$2"; shift 2
	local code
	# curl tự in '000' qua -w khi không kết nối được; '|| true' để exit lỗi của
	# curl không kích hoạt set -e làm thoát hàm. fallback khi stdout rỗng.
	code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$@" "$url" 2>/dev/null || true)"
	[[ -z "$code" ]] && code=000
	case "$code" in
		2*) ok   "$label: HTTP $code — $url" ;;
		3*) info "$label: HTTP $code (redirect) — $url" ;;
		*)  err  "$label: HTTP $code — $url" ;;
	esac
}

# Kiểm tra SSL — chỉ có ý nghĩa trên VPS có certbot; local tự bỏ qua.
check_ssl() {
	if ! command -v certbot >/dev/null 2>&1; then
		info "SSL: không thấy certbot (chạy local?) — bỏ qua kiểm tra cert."
		return 0
	fi

	# 1) Cơ chế tự gia hạn: certbot.timer (systemd) hoặc cron certbot
	if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet certbot.timer 2>/dev/null; then
		ok "SSL: certbot.timer đang chạy (tự gia hạn bật)."
	elif [[ -f /etc/cron.d/certbot ]]; then
		ok "SSL: /etc/cron.d/certbot tồn tại (tự gia hạn qua cron)."
	else
		err "SSL: KHÔNG thấy certbot.timer active hay cron certbot — tự gia hạn có thể TẮT."
		info "    Kiểm tra: systemctl status certbot.timer  |  sudo certbot renew --dry-run"
	fi

	# 2) Hạn cert thực tế đang phục vụ (openssl tới domain:443 — end-to-end)
	local host
	host="$(env_get WP_SITE_URL | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')"
	if [[ -z "$host" || "$host" == 127.0.0.1 || "$host" == localhost ]]; then
		info "SSL: WP_SITE_URL không phải domain HTTPS — bỏ qua kiểm tra hạn cert."
		return 0
	fi
	if ! command -v openssl >/dev/null 2>&1; then
		info "SSL: thiếu openssl — bỏ qua kiểm tra hạn cert."
		return 0
	fi

	local raw enddate
	if command -v timeout >/dev/null 2>&1; then
		raw="$(echo | timeout 10 openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null || true)"
	else
		raw="$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null || true)"
	fi
	enddate="$(printf '%s' "$raw" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
	if [[ -z "$enddate" ]]; then
		err "SSL: không lấy được cert từ $host:443 (chưa cấp SSL? port 443 đóng? DNS sai?)."
		return 0
	fi

	# Số ngày còn lại — date -d là GNU (Linux VPS); nếu không hỗ trợ thì chỉ in ngày hết hạn
	local exp_ts now_ts days
	exp_ts="$(date -d "$enddate" +%s 2>/dev/null || true)"
	now_ts="$(date +%s)"
	if [[ -z "$exp_ts" ]]; then
		info "SSL: cert $host hết hạn $enddate (không tính được số ngày)."
	else
		days=$(( (exp_ts - now_ts) / 86400 ))
		if (( days > 21 )); then
			ok "SSL: cert $host còn $days ngày (hết hạn $enddate)."
		elif (( days > 0 )); then
			err "SSL: cert $host còn $days ngày — SẮP HẾT HẠN (certbot thường tự gia hạn khi <30 ngày)."
		else
			err "SSL: cert $host ĐÃ HẾT HẠN ($enddate)."
		fi
	fi
}

do_healthcheck() {
	require_config || return 1
	if ! command -v curl >/dev/null 2>&1; then
		err "Cần curl để kiểm tra endpoints."
		return 1
	fi
	if [[ -z "$(docker compose ps -q wordpress 2>/dev/null)" ]]; then
		info "Container wordpress chưa chạy — kết quả có thể là lỗi kết nối (menu 5 để khởi động)."
	fi
	local base
	base="$(env_get WP_SITE_URL)"
	[[ -z "$base" ]] && base="http://127.0.0.1:$(detect_port)"
	base="${base%/}"
	info "Kiểm tra endpoints headless tại: $base"
	# REST: GET /wp-json/ trả JSON discovery → 200
	check_url "REST API" "$base/wp-json/"
	# GraphQL: POST query tối thiểu → 200 nếu WPGraphQL bật, 404 nếu chưa cài
	check_url "GraphQL " "$base/graphql" \
		-X POST -H 'Content-Type: application/json' -d '{"query":"{__typename}"}'
	# SSL/certbot — tự bỏ qua khi chạy local
	check_ssl
}

