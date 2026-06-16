# shellcheck shell=bash
# lib/ui.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# UI helpers
# ===========================================================================
C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_CYN=$'\033[36m'
C_DIM=$'\033[2m';  C_BLD=$'\033[1m';  C_RST=$'\033[0m'

err()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RST" >&2; }
ok()   { printf '%s✓ %s%s\n' "$C_GRN" "$*" "$C_RST"; }
info() { printf '%s→ %s%s\n' "$C_CYN" "$*" "$C_RST"; }

step() { # step <n> <total> "tiêu đề"
	printf '\n%s── [%s/%s] %s %s%s\n' "$C_BLD" "$1" "$2" "$3" \
		"$(printf '─%.0s' $(seq 1 $((40 - ${#3}))))" "$C_RST"
}

ask() { # ask VAR "câu hỏi" "default" — Enter/EOF = default
	local __var="$1" __q="$2" __def="${3:-}" __ans=""
	if [[ -n "$__def" ]]; then
		printf '%s%s%s %s[%s]%s: ' "$C_CYN" "$__q" "$C_RST" "$C_DIM" "$__def" "$C_RST"
	else
		printf '%s%s%s: ' "$C_CYN" "$__q" "$C_RST"
	fi
	read -r __ans || true
	printf -v "$__var" '%s' "${__ans:-$__def}"
}

confirm() { # confirm "câu hỏi" -> 0 nếu y/Y
	local reply=""
	printf '%s%s%s %s[y/N]%s: ' "$C_CYN" "$1" "$C_RST" "$C_DIM" "$C_RST"
	read -r reply || true
	[[ "$reply" =~ ^[yY]$ ]]
}

pause() {
	printf '%s(Enter để tiếp tục)%s' "$C_DIM" "$C_RST"
	read -r _ || true
	echo
}

# Chuỗi ngẫu nhiên alnum (không ký tự đặc biệt → an toàn cho .env, không cần quote).
rand() {
	LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-24}" || true
}

banner() {
	printf '%s' "$C_CYN"
	cat <<'B'
╔══════════════════════════════════════════════════════╗
║          WordPress Headless CMS — Dashboard          ║
║       WordPress + MariaDB + Redis + WP-Cron          ║
╚══════════════════════════════════════════════════════╝
B
	printf '%s' "$C_RST"
}

