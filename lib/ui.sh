# shellcheck shell=bash
# lib/ui.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# UI helpers
# ===========================================================================
C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_CYN=$'\033[36m'
C_DIM=$'\033[2m';  C_BLD=$'\033[1m';  C_RST=$'\033[0m'

# ── Lớp gum (charmbracelet) — menu/đẹp hơn, tự fallback về ANSI khi không có ──
# Phát hiện 1 lần rồi cache. Chỉ bật khi đang ở terminal tương tác (có TTY).
_GUM=""
has_gum() {
	[[ -t 0 && -t 1 ]] || return 1
	if [[ -z "$_GUM" ]]; then
		if command -v gum >/dev/null 2>&1; then _GUM=yes; else _GUM=no; fi
	fi
	[[ "$_GUM" == yes ]]
}

err()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RST" >&2; }
ok()   { printf '%s✓ %s%s\n' "$C_GRN" "$*" "$C_RST"; }
info() { printf '%s→ %s%s\n' "$C_CYN" "$*" "$C_RST"; }

step() { # step <n> <total> "tiêu đề"
	printf '\n%s── [%s/%s] %s %s%s\n' "$C_BLD" "$1" "$2" "$3" \
		"$(printf '─%.0s' $(seq 1 $((40 - ${#3}))))" "$C_RST"
}

ask() { # ask VAR "câu hỏi" "default" — Enter/EOF = default
	local __var="$1" __q="$2" __def="${3:-}" __ans=""
	if has_gum; then
		__ans="$(gum input --prompt "$__q › " --value "$__def" --width 0 || true)"
		printf -v "$__var" '%s' "${__ans:-$__def}"
		return 0
	fi
	if [[ -n "$__def" ]]; then
		printf '%s%s%s %s[%s]%s: ' "$C_CYN" "$__q" "$C_RST" "$C_DIM" "$__def" "$C_RST"
	else
		printf '%s%s%s: ' "$C_CYN" "$__q" "$C_RST"
	fi
	read -r __ans || true
	printf -v "$__var" '%s' "${__ans:-$__def}"
}

confirm() { # confirm "câu hỏi" -> 0 nếu đồng ý (mặc định No)
	if has_gum; then
		gum confirm --default=false "$1" && return 0 || return 1
	fi
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

# ui_menu "tiêu đề" "nhãn1" "nhãn2" ... — chỉ gọi khi has_gum.
# In ra (stdout) đúng nhãn được chọn; rỗng nếu người dùng huỷ (Esc).
ui_menu() {
	local header="$1"; shift
	gum choose --header "$header" --height "$(( $# + 2 ))" "$@" || true
}

# Chuỗi ngẫu nhiên alnum (không ký tự đặc biệt → an toàn cho .env, không cần quote).
rand() {
	LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-24}" || true
}

banner() {
	if has_gum; then
		gum style --border double --align center --width 54 --padding "0 1" \
			--border-foreground 44 --foreground 51 \
			"WordPress Headless CMS — Dashboard" \
			"WordPress + MariaDB + Redis + WP-Cron"
		return
	fi
	printf '%s' "$C_CYN"
	cat <<'B'
╔══════════════════════════════════════════════════════╗
║          WordPress Headless CMS — Dashboard          ║
║       WordPress + MariaDB + Redis + WP-Cron          ║
╚══════════════════════════════════════════════════════╝
B
	printf '%s' "$C_RST"
}

# Cài gum (offer) — mirror ensure_certbot. Trả 0 nếu sau cùng có gum.
ensure_gum() {
	if command -v gum >/dev/null 2>&1; then ok "Đã có gum."; _GUM=yes; return 0; fi
	local SUDO=""
	[[ "$(id -u)" != "0" ]] && SUDO="sudo"
	info "Chưa có gum (charmbracelet) — công cụ làm menu/đẹp hơn."
	if command -v brew >/dev/null 2>&1; then
		confirm "Cài gum bằng Homebrew?" || return 1
		brew install gum
	elif command -v apt-get >/dev/null 2>&1; then
		confirm "Cài gum qua kho APT của Charm?" || return 1
		$SUDO mkdir -p /etc/apt/keyrings
		curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg
		echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
			| $SUDO tee /etc/apt/sources.list.d/charm.list >/dev/null
		$SUDO apt-get update -y && $SUDO apt-get install -y gum
	elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
		local PM=yum; command -v dnf >/dev/null 2>&1 && PM=dnf
		confirm "Cài gum qua kho YUM của Charm?" || return 1
		printf '%s\n' \
			'[charm]' \
			'name=Charm' \
			'baseurl=https://repo.charm.sh/yum/' \
			'enabled=1' \
			'gpgcheck=1' \
			'gpgkey=https://repo.charm.sh/yum/gpg.key' \
			| $SUDO tee /etc/yum.repos.d/charm.repo >/dev/null
		$SUDO "$PM" install -y gum
	else
		err "Không nhận diện được trình quản lý gói."
		info "Cài thủ công: https://github.com/charmbracelet/gum#installation"
		return 1
	fi
	if command -v gum >/dev/null 2>&1; then
		_GUM=yes; ok "Đã cài gum. Menu sẽ đẹp hơn từ giờ."; return 0
	fi
	err "Cài gum chưa thành công."; return 1
}
