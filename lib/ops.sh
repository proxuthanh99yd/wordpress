# shellcheck shell=bash
# lib/ops.sh — nạp bởi setup.sh (source). Không chạy độc lập.

# ===========================================================================
# Vận hành
# ===========================================================================
require_config() {
	if [[ ! -f docker-compose.yml || ! -f .env ]]; then
		err "Chưa có cấu hình — chạy wizard trước (menu 1)."
		return 1
	fi
}

do_up()      { require_config && { docker compose up -d; docker compose ps; }; }
do_down()    { require_config && docker compose down; }
do_restart() { require_config && { docker compose restart; docker compose ps; }; }

do_update() {
	require_config || return 1
	err "Nên backup trước khi update (menu b)."
	confirm "Tiếp tục pull image mới + up -d?" || return 0
	docker compose pull
	docker compose up -d
	docker compose ps
}

do_logs() {
	require_config || return 1
	local svc=""
	ask svc "Service (wordpress/db/redis/wpcron, trống = tất cả)" ""
	if confirm "Follow logs? (Ctrl-C để quay lại menu)"; then
		trap ' ' INT
		# shellcheck disable=SC2086
		docker compose logs -f --tail=100 $svc || true
		trap - INT
		echo
	else
		# shellcheck disable=SC2086
		docker compose logs --tail=100 $svc || true
	fi
}

do_status() {
	require_config || return 1
	info "Containers:"
	docker compose ps
	echo
	info "Tài nguyên:"
	local ids
	ids="$(docker compose ps -q 2>/dev/null || true)"
	if [[ -n "$ids" ]]; then
		# shellcheck disable=SC2086
		docker stats --no-stream $ids 2>/dev/null || true
	else
		echo "  (stack chưa chạy)"
	fi
	echo
	info "Redis object cache:"
	docker compose exec -T redis redis-cli info memory 2>/dev/null | grep -E 'used_memory_human|maxmemory_human|maxmemory_policy' || echo "  (redis chưa chạy)"
	docker compose exec -T redis redis-cli dbsize 2>/dev/null | sed 's/^/  keys: /' || true
	echo
	info "Dung lượng dữ liệu:"
	du -sh mysql-data public_html/wp-content/uploads backups 2>/dev/null | sed 's/^/  /' || true
}

