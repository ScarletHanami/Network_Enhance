#!/system/bin/sh
# service.sh — 网络增强
# AxManager BOOT_COMPLETED late_start service 阶段

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh"; return 0
    fi
    if [ -n "${MODPATH:-}" ] && [ -f "$MODPATH/scripts/common.sh" ] 2>/dev/null; then
        echo "$MODPATH/scripts/common.sh"; return 0
    fi
    local raw_zero="${0:-}"
    if [ -n "$raw_zero" ] && [ "$raw_zero" != "${raw_zero#/}" ]; then
        local d="${raw_zero%/*}"
        [ -f "$d/scripts/common.sh" ] 2>/dev/null && { echo "$d/scripts/common.sh"; return 0; }
        [ -f "$d/../scripts/common.sh" ] 2>/dev/null && { echo "$d/../scripts/common.sh"; return 0; }
    fi
    for _p in \
        /data/user_de/0/com.android.shell/axeron/plugins/Network_Enhance \
        /data/user_de/0/android/axeron/plugins/Network_Enhance \
        /data/adb/modules/Network_Enhance; do
        [ -f "$_p/scripts/common.sh" ] 2>/dev/null && { echo "$_p/scripts/common.sh"; return 0; }
    done
    return 1
}
_se_common=$(_se_find_common) || { echo "[NE] common.sh 未找到" >&2; exit 0; }
. "$_se_common"
unset _se_common
unset -f _se_find_common 2>/dev/null || true

sleep 3
se_ci_log "service.sh" "service.sh 启动 (late_start) | pwd=$(pwd 2>/dev/null)"
log_msg "网络增强 v${SE_VERSION} service.sh 启动 (late_start) pwd=$(pwd)" "[boot]"

# ===============================
# late_start 阶段验证 — 重新应用 settings, 防止系统重置
# ===============================
verify_and_reapply() {
    se_ci_log "service.sh" "verify_and_reapply: entry"
    [ "$ENABLE_LATE_VERIFY" = "true" ] || return 0
    log_msg "开始 late_start 阶段验证..." "[verify]"
    local reapply_count=0

    if [ "$ENABLE_WIFI_OPTIMIZE" = "true" ]; then
        if [ "$(se_get global wifi_scan_throttle_enabled)" != "0" ]; then
            se_put global wifi_scan_throttle_enabled 0
            reapply_count=$((reapply_count + 1))
        fi
        if [ "$(se_get global wifi_suspend_optimizations_enabled)" != "0" ]; then
            se_put global wifi_suspend_optimizations_enabled 0
            reapply_count=$((reapply_count + 1))
        fi
        if [ "$(se_get global mobile_data_always_on)" != "1" ] && [ "$ENABLE_MOBILE_OPTIMIZE" = "true" ]; then
            se_put global mobile_data_always_on 1
            reapply_count=$((reapply_count + 1))
        fi
    fi

    if [ "$ENABLE_PRIVATE_DNS" = "true" ]; then
        local cur_mode cur_spec
        cur_mode=$(se_get global private_dns_mode)
        cur_spec=$(se_get global private_dns_spec)
        if [ "$cur_mode" != "hostname" ] || [ "$cur_spec" != "$PRIVATE_DNS_HOST" ]; then
            if wait_network_ready 10; then
                local dot_ok=0
                if command -v nc >/dev/null 2>&1 && nc -w 5 -z "$PRIVATE_DNS_HOST" 853 2>/dev/null; then
                    dot_ok=1
                elif ping -c 1 -W 3 "$PRIVATE_DNS_HOST" >/dev/null 2>&1; then
                    dot_ok=1
                fi
                if [ "$dot_ok" = "1" ]; then
                    se_put global private_dns_mode "hostname"
                    se_put global private_dns_spec "$PRIVATE_DNS_HOST"
                    reapply_count=$((reapply_count + 1))
                fi
            fi
        fi
    fi

    log_msg "late_start 验证完成 | 重应用 ${reapply_count} 项" "[verify]"
    return 0
}

# ===============================
# DNS 预热 — 后台执行, 不阻塞
# ===============================
apply_dns_prefetch() {
    se_ci_log "service.sh" "apply_dns_prefetch: entry"
    [ "$ENABLE_DNS_PREFETCH" = "true" ] || return 0
    if ! wait_network_ready 10; then
        log_msg "网络未就绪，跳过 DNS 预热" "[dns]"
        return 0
    fi
    (
        # DNS 预热: ping 域名触发 DNS 解析缓存, 加速首次访问
        for domain in www.baidu.com www.qq.com www.taobao.com www.jd.com \
            dns.alidns.com dot.pub dns.360.cn \
            www.douyin.com www.bilibili.com www.kuaishou.com \
            www.weixin.qq.com www.tencent.com www.mi.com; do
            ping -c 1 -W 1 "$domain" >/dev/null 2>&1
        done
    ) &
    log_msg "DNS 预热已启动 (后台)" "[dns]"
    return 0
}

# ===============================
# 网络状态快照
# ===============================
log_network_snapshot() {
    se_ci_log "service.sh" "log_network_snapshot: entry"
    log_msg "--- 网络状态快照 ---" "[snapshot]"
    local mccmnc carrier_name
    mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
    carrier_name=$(getprop gsm.sim.operator.alpha 2>/dev/null)
    log_msg "  SIM: ${carrier_name:-无} (${mccmnc:-未知})" "[snapshot]"
    log_msg "  WiFi RSSI: $(se_get_wifi_rssi)" "[snapshot]"
    log_msg "  NR RSRP: $(se_get_nr_rsrp)" "[snapshot]"
    log_msg "  NR SINR: $(se_get_nr_sinr)" "[snapshot]"
    log_msg "--- 快照结束 ---" "[snapshot]"
    return 0
}

# ===============================
# 启动智能调度器（monitor.sh 主循环）
# ===============================
# monitor.sh 主循环必须且只能在此 (late_start) 阶段通过 nohup 后台启动,
# 不阻塞 service.sh。启动前调用 wait_network_ready 确保网络就绪。
start_smart_monitor() {
    se_ci_log "service.sh" "start_smart_monitor: entry"
    [ "$ENABLE_MONITOR" = "true" ] || return 0
    if [ ! -f "$MODDIR/scripts/monitor.sh" ]; then
        log_msg "调度器脚本缺失，跳过启动" "[monitor]"
        return 0
    fi

    # 等待网络就绪（最多 30 秒）
    log_msg "等待网络就绪后启动调度器..." "[monitor]"
    if ! wait_network_ready 30; then
        log_msg "网络未就绪, 调度器仍将启动 (将在循环中等待网络)" "[monitor]"
    fi

    # 通过 nohup 后台启动 monitor.sh
    # monitor.sh start 内部会 fork _loop 子进程
    sh "$MODDIR/scripts/monitor.sh" start 2>>"$SE_LOG_FILE"
    log_msg "智能调度器启动请求已发送" "[monitor]"
    return 0
}

# ===============================
# 主流程
# ===============================
se_ci_log "service.sh" "主流程: verify_and_reapply"
verify_and_reapply
se_ci_log "service.sh" "主流程: apply_dns_prefetch"
apply_dns_prefetch
se_ci_log "service.sh" "主流程: log_network_snapshot"
log_network_snapshot
se_ci_log "service.sh" "主流程: start_smart_monitor"
start_smart_monitor

se_ci_log "service.sh" "service.sh 完成"
log_msg "service.sh 完成，模块就绪" "[boot]"
exit 0
