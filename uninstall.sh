#!/system/bin/sh
# uninstall.sh — 网络增强 卸载清理脚本
#
# 卸载时执行完整清理: 
#   1. 停止调度器进程, 关闭 Data Saver (防止残留导致后台应用无法联网)
#   2. 联动 carrier.sh unlock-lte 恢复网络制式为默认 5G 模式
#   3. 深度清理所有运行时残留文件 (PID/状态/日志/临时文件)
#   4. 还原 WiFi / 移动网络 / Private DNS 设置

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

# 尝试加载 common.sh（卸载时可能 MODPATH 已被移除，需容错）
_se_common=$(_se_find_common 2>/dev/null)
if [ -n "$_se_common" ]; then
    . "$_se_common" 2>/dev/null
fi
unset _se_common
unset -f _se_find_common 2>/dev/null || true

se_ci_log "uninstall.sh" "uninstall.sh 启动"

# 卸载时日志可能无法写入（模块目录可能已移除），用临时函数兜底
_uninstall_log() {
    local msg="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "?")
    # 尝试写入模块日志（如仍可访问）
    if [ -n "${SE_LOG_FILE:-}" ] && [ -w "$(dirname "$SE_LOG_FILE" 2>/dev/null)" ] 2>/dev/null; then
        echo "$ts [uninstall] $msg" >> "$SE_LOG_FILE" 2>/dev/null
    fi
    # 同时输出到 stderr（AxManager 可捕获）
    echo "[NE uninstall] $msg" >&2
}

_uninstall_log "开始卸载清理..."

se_ci_log "uninstall.sh" "停止调度器"

# ===============================
# 停止调度器进程
# ===============================
# 先停止 monitor.sh 主循环，避免卸载过程中进程仍在运行
if [ -n "${SE_PID_FILE:-}" ] && [ -f "$SE_PID_FILE" ]; then
    mon_pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    if [ -n "$mon_pid" ] && kill -0 "$mon_pid" 2>/dev/null; then
        kill "$mon_pid" 2>/dev/null
        sleep 1
        kill -9 "$mon_pid" 2>/dev/null
        _uninstall_log "调度器进程已停止 (PID=$mon_pid)"
    fi
fi

# 兜底：通过 pkill 杀掉所有 monitor.sh 后台进程
# 注意：免Root下 pkill 可能受限，仅作为补充手段
pkill -f "monitor.sh" 2>/dev/null
sleep 0.5

# ===============================
# 关闭 Data Saver (必须关闭, 防止残留导致后台应用无法联网)
# ===============================
# 系统级开关, 即使模块异常卸载也要确保还原
if command -v cmd >/dev/null 2>&1; then
    if cmd netpolicy set restrict-background false 2>/dev/null; then
        _uninstall_log "Data Saver 已关闭 (restrict-background=false)"
        se_ci_log "uninstall.sh" "关闭 Data Saver"
    else
        _uninstall_log "WARN: cmd netpolicy 关闭 Data Saver 失败 (部分 ROM 不支持)"
    fi
fi

# ===============================
# 联动 carrier.sh unlock-lte 恢复网络制式
# ===============================
# 恢复网络制式为运营商默认 5G 模式
# 同时清除 PNM 受限标记
if [ -n "${MODDIR:-}" ] && [ -f "$MODDIR/scripts/carrier.sh" ]; then
    sh "$MODDIR/scripts/carrier.sh" unlock-lte >/dev/null 2>&1
    _uninstall_log "已调用 carrier.sh unlock-lte 恢复网络制式"
    se_ci_log "uninstall.sh" "恢复网络制式"
elif [ -n "${MODPATH:-}" ] && [ -f "$MODPATH/scripts/carrier.sh" ]; then
    sh "$MODPATH/scripts/carrier.sh" unlock-lte >/dev/null 2>&1
    _uninstall_log "已调用 carrier.sh unlock-lte 恢复网络制式"
    se_ci_log "uninstall.sh" "恢复网络制式"
else
    # 模块目录已移除，手动恢复 PNM
    # 使用各运营商默认值（手动恢复 PNM=26）
    settings put global preferred_network_mode 26 2>/dev/null  # 默认联通兼容
    settings put global preferred_network_mode1 26 2>/dev/null
    settings put global endc_capability 1 2>/dev/null
    _uninstall_log "carrier.sh 不可访问, 手动恢复 PNM=26 (默认)"
fi

# ===============================
# Private DNS 恢复默认
# ===============================
settings delete global private_dns_mode 2>/dev/null
settings delete global private_dns_spec 2>/dev/null
settings put global private_dns_mode "opportunistic" 2>/dev/null
_uninstall_log "Private DNS 已恢复为系统默认"

# ===============================
# WiFi 设置还原
# ===============================
settings put global wifi_scan_throttle_enabled 1 2>/dev/null
settings put global wifi_framework_scan_interval_ms 30000 2>/dev/null
settings put global wifi_suspend_optimizations_enabled 1 2>/dev/null
settings delete global wifi_idle_ms 2>/dev/null
settings delete global wifi_bad_rssi_threshold 2>/dev/null
settings delete global wifi_bad_rssi_threshold_2g 2>/dev/null
settings delete global wifi_bad_rssi_threshold_5g 2>/dev/null
settings put global wifi_networks_score_enabled 1 2>/dev/null
settings delete global wifi_max_dwell_time_ms 2>/dev/null
settings delete global wifi_enhanced_mac_randomization_enabled 2>/dev/null
settings delete global wifi_connected_mac_randomization_enabled 2>/dev/null
settings delete global wifi_pno_frequency_threshold 2>/dev/null
settings delete global wifi_persistent_group_remove_delay_ms 2>/dev/null
settings delete global wifi_batched_scan_results_ms 2>/dev/null
settings delete global wifi_recovery_state 2>/dev/null
_uninstall_log "WiFi 设置已还原"

se_ci_log "uninstall.sh" "WiFi/移动网络/Private DNS 还原完成"

# ===============================
# 移动网络设置还原
# ===============================
settings put global mobile_data_always_on 0 2>/dev/null
settings delete global mobile_data_preferred 2>/dev/null
settings delete global mobile_data_auto_handover 2>/dev/null
settings delete global preferred_network_mode1 2>/dev/null
settings delete global preferred_network_mode 2>/dev/null
settings delete global nr_sa_mode 2>/dev/null
settings delete global vonr_enabled 2>/dev/null
settings delete global enable_nr_dc 2>/dev/null
settings delete global endc_capability 2>/dev/null
settings delete global nr_handover_enabled 2>/dev/null
settings delete global data_stall_alarm_aggressive 2>/dev/null
settings delete global data_stall_alarm_non_aggressive 2>/dev/null
settings delete global vt_enabled 2>/dev/null
settings put global volte_vt_enabled 1 2>/dev/null
_uninstall_log "移动网络设置已还原"

# weaknet 额外项
settings put global low_power_mode 0 2>/dev/null
settings put global low_power_sticky 0 2>/dev/null

# 清理自定义键（post-fs-data.sh 迁移自 system.prop）
settings delete global network_enhance_version 2>/dev/null
settings delete global network_enhance_activated 2>/dev/null
_uninstall_log "自定义键已清理"

# ===============================
# 深度清理所有运行时残留文件
# ===============================
_uninstall_log "开始深度清理运行时残留文件..."

# PID 文件
rm -f /data/local/tmp/network_enhance_monitor.pid 2>/dev/null
# 状态文件
rm -f /data/local/tmp/network_enhance_monitor.state 2>/dev/null
# 状态临时文件
rm -f /data/local/tmp/network_enhance_monitor.state.tmp 2>/dev/null
# 日志文件（含轮转临时文件）
rm -f /data/local/tmp/Network_Enhance/network_enhance.log 2>/dev/null
rm -f /data/local/tmp/Network_Enhance/network_enhance.log.tmp 2>/dev/null
rm -f /data/local/tmp/Network_Enhance/network_enhance.log.* 2>/dev/null
# 5G 备份文件（carrier.sh lock-lte 保存的 PNM 备份）
rm -f /data/local/tmp/network_enhance_5g_backup 2>/dev/null
# PNM 受限标记文件（所有品牌）
rm -f /data/local/tmp/network_enhance_pnm_restricted_* 2>/dev/null
# weaknet 激活标志文件
rm -f /data/local/tmp/network_enhance_weaknet_active 2>/dev/null
# DNS 预热 PID 锁
rm -f /data/local/tmp/network_enhance_dns_prefetch.pid 2>/dev/null

# 兜底：清理所有 network_enhance 前缀的临时文件
# 注意：使用 rm -f 不会报错，即使文件不存在
for _f in /data/local/tmp/network_enhance*; do
    [ -f "$_f" ] 2>/dev/null && rm -f "$_f" 2>/dev/null
done

# 清理 CI 调试日志（大写 N，与 network_enhance* 不同前缀）
rm -f "/data/local/tmp/Network_Enhance/ci.log" 2>/dev/null

# 清理 dumpsys 缓存目录
rm -rf "/data/local/tmp/network_enhance_dumpsys_cache" 2>/dev/null

_uninstall_log "运行时残留文件已清理"
se_ci_log "uninstall.sh" "运行时文件清理"

# ===============================
# 撤销所有通知
# ===============================
cmd notification cancel network_enhance_monitor 2>/dev/null
_uninstall_log "通知已撤销"

_uninstall_log "网络增强 已卸载"
exit 0
