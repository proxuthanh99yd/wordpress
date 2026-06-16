# shellcheck shell=bash
# lib/status.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Trạng thái
# ===========================================================================
svc_dot() { # svc_dot <service> — chấm màu theo health/state
	local cid st
	cid="$(docker compose ps -q "$1" 2>/dev/null | head -1 || true)"
	if [[ -z "$cid" ]]; then printf '%s○%s' "$C_DIM" "$C_RST"; return; fi
	st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
	case "$st" in
		healthy|running)     printf '%s●%s' "$C_GRN" "$C_RST" ;;
		starting|restarting) printf '%s●%s' "$C_YLW" "$C_RST" ;;
		*)                   printf '%s●%s' "$C_RED" "$C_RST" ;;
	esac
}

detect_project() { grep -m1 -oE 'project: .*' .env 2>/dev/null | cut -d' ' -f2- || true; }
detect_port()    { grep -m1 -oE '127\.0\.0\.1:[0-9]+' docker-compose.yml 2>/dev/null | cut -d: -f2 || true; }
env_get()        { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }

panel() {
	if [[ ! -f .env || ! -f docker-compose.yml ]]; then
		printf ' %sChưa có cấu hình — chọn 1) Cài đặt mới để bắt đầu.%s\n\n' "$C_YLW" "$C_RST"
		return
	fi
	local proj port url
	proj="$(detect_project)"; port="$(detect_port)"; url="$(env_get WP_SITE_URL)"
	printf ' %sProject%s : %-22s %sURL%s: %s\n' "$C_DIM" "$C_RST" "${proj:-?}" "$C_DIM" "$C_RST" "${url:-http://127.0.0.1:${port:-9000}}"
	printf ' %sLocal%s   : http://127.0.0.1:%-8s %sCORS%s: %s\n' "$C_DIM" "$C_RST" "${port:-9000}" "$C_DIM" "$C_RST" "$(env_get FRONTEND_ORIGIN)"
	printf ' %sServices%s: %s wordpress  %s db  %s redis  %s wpcron\n\n' "$C_DIM" "$C_RST" \
		"$(svc_dot wordpress)" "$(svc_dot db)" "$(svc_dot redis)" "$(svc_dot wpcron)"
}

