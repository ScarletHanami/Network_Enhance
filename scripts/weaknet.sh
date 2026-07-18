#!/system/bin/sh
# weaknet.sh — 网络增强 v1.0 弱网自救脚本
#
# ⚠️ 修改点 1: 游戏模式重构（S3 + 用户补充要求 2）
#   - 调用 carrier.sh lock-lte (mode=11 LTE only + ENDC=0)
#   - 调用 cmd netpolicy set restrict-background true (禁后台抢带宽)
#   - 发送 LTE Only 语音副作用通知（用户约束 3）
# ⚠️ 修改点 2: 恢复默认模式重构（用户细节 1+2）
#   - 绝对还原 Data Saver: cmd netpolicy set restrict-background false
#   - 联动调用 carrier.sh unlock-lte (不散写 settings put)
# ⚠️ 修改点 3: 视频模式优化（用户细节 2: DNS 预热域名明确）
# ⚠️ 修改点 4: 命名统一为 network_enhance / v1.0
#
# 来源:
#   S1 第一步: 原模块 v6.3.0 弱网自救框架
#   S3 第三步: cmd netpolicy 子命令 + 4G+ 跳频防护
#   用户补充要求 2: 游戏模式锁定 LTE only
#   用户约束 3: LTE Only 语音副作用通知
#   用户细节 1: Data Saver 绝对还原
#   用户细节 2: 联动调用 unlock-lte

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh"; return 0
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
unset _se_common _se_find_common

# ----------------------------------------------------------------------
# weaknet 激活/退出标志管理（保留 S1）
# ----------------------------------------------------------------------
set_weaknet_active() {
    touch "$WEAKNET_ACTIVE_FLAG" 2>/dev/null
    log_msg "weaknet 模式激活 ($1)" "[weaknet]"
    return 0
}

clear_weaknet_active() {
    rm -f "$WEAKNET_ACTIVE_FLAG" 2>/dev/null
    log_msg "weaknet 模式退出" "[weaknet]"
    return 0
}

# ----------------------------------------------------------------------
# 修改点 3: LTE Only 语音副作用通知（用户约束 3）
# ----------------------------------------------------------------------
# 来源: 用户约束 3
# lock_lte() 使用 mode=11 (LTE only), 在免Root下会导致非 VoLTE 环境的电话无法接入
# (无法回落 2/3G), 必须明确告知用户
notify_lte_only_voice_warning() {
    local title="网络增强 → LTE Only 已锁定"
    local body="已锁定 LTE Only 模式\n\n注意: 非 VoLTE 来电可能无法接通\n游戏结束请及时解锁 (菜单 32)"
    se_notify "$title" "$body"
    log_msg "[通知] LTE Only 语音副作用警告已发送" "[weaknet]"
    return 0
}

# ----------------------------------------------------------------------
# DNS 预热（保留 S1 框架）
# ----------------------------------------------------------------------
# 用户细节 2 明确: 这是 DNS 预热 (ping 域名触发 DNS 解析缓存), 不是调用 API
dns_prefetch() {
    local tag="$1"
    shift
    if ! wait_network_ready 3; then
        log_msg "DNS 预热跳过 (网络未就绪): $tag" "[weaknet]"
        return 0
    fi
    if [ -f "$DNS_PREFETCH_PID" ]; then
        local old_pid
        old_pid=$(cat "$DNS_PREFETCH_PID" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            if [ -r "/proc/$old_pid/cmdline" ]; then
                if tr '\0' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null | grep -q "ping"; then
                    log_msg "DNS 预热已在运行 (PID=$old_pid)" "[weaknet]"
                    return 0
                fi
            else
                log_msg "DNS 预热可能已在运行 (PID=$old_pid)" "[weaknet]"
                return 0
            fi
        fi
        rm -f "$DNS_PREFETCH_PID" 2>/dev/null
    fi
    (
        for domain in "$@"; do
            ping -c 1 -W 1 "$domain" >/dev/null 2>&1
        done
        rm -f "$DNS_PREFETCH_PID" 2>/dev/null
    ) &
    echo $! > "$DNS_PREFETCH_PID" 2>/dev/null
    log_msg "DNS 预热已启动 (PID=$!): $tag" "[weaknet]"
    return 0
}

# ----------------------------------------------------------------------
# 静默重置（保留 S1 框架, 修改点 4: 命名统一）
# ----------------------------------------------------------------------
silent_reset() {
    if [ -f "$MODDIR/scripts/wifi.sh" ]; then
        sh "$MODDIR/scripts/wifi.sh" apply >/dev/null 2>&1
    fi
    if [ -f "$MODDIR/scripts/carrier.sh" ]; then
        sh "$MODDIR/scripts/carrier.sh" apply >/dev/null 2>&1
    fi
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global data_stall_alarm_aggressive 0
    se_put global data_stall_alarm_non_aggressive 0
    se_del global wifi_batched_scan_results_ms
    se_del global wifi_recovery_state
    se_put global mobile_data_preferred 1
    se_put global wifi_idle_ms "$WIFI_IDLE_MS"
    se_put global wifi_persistent_group_remove_delay_ms 30000
    local current_carrier
    current_carrier=$(se_detect_carrier)
    if [ "$current_carrier" != "mobile" ] && [ "$current_carrier" != "ctn" ]; then
        se_del global nr_sa_mode
    elif [ "$ENABLE_5G_SA" != "true" ]; then
        se_del global nr_sa_mode
    fi
    return 0
}

# ----------------------------------------------------------------------
# 修改点 1+2+3: 视频模式优化（用户细节 2: DNS 预热域名明确列出）
# ----------------------------------------------------------------------
# 来源: S1 原模块 + 用户原始要求 4 (视频模式增加缓冲策略优化 + 弱网预加载)
# DNS 预热说明: 通过 ping 域名触发系统 DNS 解析缓存, 加速首次访问
#   不是调用视频平台的 API, 而是预热 DNS 解析
apply_video_mode() {
    echo "=== 应用视频模式 (v1.0) ==="
    silent_reset

    # WiFi 弱信号容忍 + 扫描优化
    se_put global wifi_bad_rssi_threshold_2g "-95"
    se_put global wifi_bad_rssi_threshold_5g "-92"
    se_put global wifi_bad_rssi_threshold "-95"
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_idle_ms 14400000
    se_put global wifi_framework_scan_interval_ms 10000
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_batched_scan_results_ms 5000
    se_put global wifi_recovery_state 1

    # 移动数据保活
    se_put global mobile_data_always_on 1
    se_put global mobile_data_auto_handover 1
    se_put global mobile_data_preferred 0
    se_put global data_stall_alarm_aggressive 1
    se_put global data_stall_alarm_non_aggressive 1

    # 关闭低功耗
    se_put global low_power_mode 0
    se_put global low_power_sticky 0

    # VoLTE/VoNR
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    echo "  [OK] 视频模式优化已应用"

    # DNS 预热视频平台域名（用户细节 2: 明确列出具体域名）
    # 短视频平台: 抖音/快手/西瓜/B站
    # 长视频平台: 爱奇艺/优酷
    # 视频 API 加速: 抖音/B站 API 域名
    # DoT 提供商: 阿里/腾讯
    dns_prefetch "video" \
        www.douyin.com v.douyin.com api.amemv.com api2.amemv.com \
        www.bilibili.com api.bilibili.com \
        www.kuaishou.com www.ixigua.com \
        www.iqiyi.com www.youku.com \
        dns.alidns.com dot.pub

    set_weaknet_active "video"
    log_msg "视频模式已应用" "[weaknet]"
    echo "[OK] 视频模式已生效"
    return 0
}

# ----------------------------------------------------------------------
# 修改点 1+2+3: 游戏模式重构（S3 + 用户补充要求 2 + 用户约束 3）
# ----------------------------------------------------------------------
# 来源:
#   S3 RILConstants.java NETWORK_MODE_LTE_ONLY = 11
#   S3 cmd netpolicy set restrict-background (Android Developer 文档)
#   用户补充要求 2: 4G+ 跳频防护
#   用户约束 3: LTE Only 语音副作用通知
#
# 关键改动（与 S1 原模块完全相反）:
#   S1 原模块游戏模式: 开启 5G SA + DC + ENDC (鼓励载波聚合)
#   新模块游戏模式:   锁定 LTE only + 关闭 ENDC + 禁后台抢带宽
#
# 流程:
#   1. silent_reset 清理状态
#   2. 调用 carrier.sh lock-lte (mode=11 + ENDC=0 + 功能性验证)
#   3. 调用 cmd netpolicy set restrict-background true (禁后台抢带宽)
#   4. WiFi 弱信号容忍 + 扫描优化
#   5. DNS 预热游戏厂商
#   6. 发送 LTE Only 语音副作用通知（用户约束 3）
#   7. set_weaknet_active "game" (monitor.sh 将严格隔离)
apply_game_mode() {
    echo "=== 应用游戏模式 (v1.0 锁定 LTE 版) ==="
    silent_reset

    # 关键 1: 调用 carrier.sh lock-lte 锁定 LTE only
    # 解决 4G+ 跳频断流问题 (用户补充要求 2)
    # carrier.sh 内部会: 保存当前 PNM → 写入 mode=11 → 关闭 ENDC → 功能性验证
    echo "  [..] 锁定 LTE only (mode=11, 关闭 ENDC)..."
    if [ -f "$MODDIR/scripts/carrier.sh" ]; then
        sh "$MODDIR/scripts/carrier.sh" lock-lte >/dev/null 2>&1
    else
        log_msg "[game] carrier.sh 未找到, 跳过 lock-lte" "[warn]"
    fi

    # 关键 2: 移动数据保活
    se_put global mobile_data_always_on 1
    se_put global mobile_data_preferred 1
    se_put global mobile_data_auto_handover 1

    # 关闭低功耗
    se_put global low_power_mode 0
    se_put global low_power_sticky 0

    # WiFi 优化（弱信号容忍, 减少扫描中断）
    se_put global wifi_framework_scan_interval_ms 10000
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_bad_rssi_threshold "-90"
    se_put global wifi_bad_rssi_threshold_2g "-90"
    se_put global wifi_bad_rssi_threshold_5g "-88"
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global wifi_idle_ms 21600000
    se_put global wifi_batched_scan_results_ms 5000
    se_put global wifi_recovery_state 1

    # VoLTE 启用（LTE only 下语音依赖 VoLTE）
    se_put global volte_vt_enabled 1

    # 关键 3: 开启 Data Saver 禁止后台抢带宽（S3 cmd netpolicy）
    # 来源: Android Developer https://developer.android.com/develop/connectivity/network-ops/data-saver
    # 此开关为系统级, 会影响所有应用的后台数据使用
    echo "  [..] 开启 Data Saver (禁止后台应用抢带宽)..."
    if cmd netpolicy set restrict-background true 2>/dev/null; then
        echo "  [OK] Data Saver 已开启"
        log_msg "[game] Data Saver 已开启 (restrict-background=true)" "[weaknet]"
    else
        echo "  [WARN] Data Saver 开启失败 (部分 ROM 不支持)"
        log_msg "[game] cmd netpolicy set restrict-background true 失败" "[warn]"
    fi

    echo "  [OK] 游戏模式已锁定 LTE only + 关闭 ENDC + 禁后台带宽"

    # DNS 预热游戏厂商
    # 腾讯系: 王者荣耀/和平精英
    # 网易系: 阴阳师/荒野行动
    # 米哈游: 原神/崩坏
    # DoT 提供商: 阿里/腾讯
    dns_prefetch "game" \
        dns.alidns.com dot.pub \
        www.tencent.com www.netease.com www.mihoyo.com \
        api.tencentcloudapi.com

    # 关键 4: 发送 LTE Only 语音副作用通知（用户约束 3）
    notify_lte_only_voice_warning

    set_weaknet_active "game"
    log_msg "游戏模式已应用 (LTE锁定版 + Data Saver)" "[weaknet]"
    echo "[OK] 游戏模式已生效"
    echo ""
    echo "  注意: 已锁定 LTE Only, 非 VoLTE 来电可能无法接通"
    echo "  游戏结束请执行 '恢复默认优化' (菜单 5) 或 '解锁 LTE' (菜单 32)"
    return 0
}

# ----------------------------------------------------------------------
# 社交模式（保留 S1 框架 + 修改点 4: 命名统一）
# ----------------------------------------------------------------------
apply_social_mode() {
    echo "=== 应用社交模式 (v1.0) ==="
    silent_reset

    se_put global mobile_data_always_on 1
    se_put global mobile_data_auto_handover 1
    se_put global mobile_data_preferred 0
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_idle_ms 14400000
    se_put global wifi_scan_throttle_enabled 0
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global wifi_bad_rssi_threshold "-90"
    se_put global wifi_bad_rssi_threshold_2g "-90"
    se_put global wifi_bad_rssi_threshold_5g "-88"
    se_put global wifi_networks_score_enabled 0
    se_put global data_stall_alarm_aggressive 1
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global wifi_recovery_state 1
    se_put global volte_vt_enabled 1
    echo "  [OK] 社交模式已应用"

    # DNS 预热社交平台
    # 微信/QQ: 即时通讯
    # DNS: 阿里/腾讯/DNSPod
    dns_prefetch "social" \
        dns.alidns.com dot.pub dns.pub \
        www.weixin.qq.com wx.qq.com \
        www.qq.com mobile.qq.com \
        im.qq.com

    set_weaknet_active "social"
    log_msg "社交模式已应用" "[weaknet]"
    echo "[OK] 社交模式已生效"
    return 0
}

# ----------------------------------------------------------------------
# 下载模式（保留 S1 框架 + 修改点 4: 命名统一）
# ----------------------------------------------------------------------
apply_download_mode() {
    echo "=== 应用下载模式 (v1.0) ==="
    silent_reset

    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_idle_ms 21600000
    se_put global wifi_bad_rssi_threshold "-92"
    se_put global wifi_bad_rssi_threshold_2g "-92"
    se_put global wifi_bad_rssi_threshold_5g "-90"
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global mobile_data_always_on 1
    se_put global mobile_data_auto_handover 1
    se_put global mobile_data_preferred 0
    se_put global wifi_batched_scan_results_ms 5000
    se_put global wifi_recovery_state 1
    se_put global data_stall_alarm_aggressive 1
    se_put global data_stall_alarm_non_aggressive 1
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    echo "  [OK] 下载模式已应用"

    # DNS 预热下载平台
    # 电商: 淘宝/京东
    # 网盘: 百度网盘/123pan
    # CDN: jsdelivr
    # DoT: 阿里/腾讯
    dns_prefetch "download" \
        dns.alidns.com dot.pub \
        www.baidu.com www.taobao.com www.jd.com \
        www.aliyun.com cdn.jsdelivr.net \
        pan.baidu.com www.123pan.com

    set_weaknet_active "download"
    log_msg "下载模式已应用" "[weaknet]"
    echo "[OK] 下载模式已生效"
    return 0
}

# ----------------------------------------------------------------------
# 修改点 2: 恢复默认优化模式（用户细节 1+2 核心！）
# ----------------------------------------------------------------------
# 来源:
#   用户细节 1: Data Saver 绝对还原 (避免后台应用彻底无法联网)
#   用户细节 2: 联动调用 carrier.sh unlock-lte (不散写 settings put)
#
# 流程:
#   1. clear_weaknet_active (清除 weaknet 标志, 让 monitor.sh 恢复工作)
#   2. 绝对还原 Data Saver: cmd netpolicy set restrict-background false
#   3. 联动调用 carrier.sh unlock-lte (恢复 PNM + ENDC + 清除受限标记 + 功能性验证)
#   4. 重置 WiFi/移动数据 settings
#   5. 清理 DNS 预热 PID
#   6. 重启 monitor.sh (如果配置启用)
apply_normal_mode() {
    echo "=== 恢复默认优化模式 ==="
    clear_weaknet_active

    # 关键 1: 绝对还原 Data Saver（用户细节 1 核心！）
    # 此开关为系统级, 必须确保关闭, 否则用户日常后台应用彻底无法联网
    echo "  [..] 还原 Data Saver (恢复后台数据权限)..."
    if cmd netpolicy set restrict-background false 2>/dev/null; then
        echo "  [OK] Data Saver 已关闭"
        log_msg "[normal] Data Saver 已关闭 (restrict-background=false)" "[weaknet]"
    else
        echo "  [WARN] Data Saver 关闭失败 (部分 ROM 不支持)"
        log_msg "[normal] cmd netpolicy set restrict-background false 失败" "[warn]"
    fi

    # 关键 2: 联动调用 carrier.sh unlock-lte（用户细节 2 核心！）
    # 不散写 settings put, 确保 PNM 恢复 + ENDC 恢复 + PNM 受限标记清除 + 功能性验证 联动执行
    echo "  [..] 调用 carrier.sh unlock-lte (恢复 5G + ENDC)..."
    if [ -f "$MODDIR/scripts/carrier.sh" ]; then
        sh "$MODDIR/scripts/carrier.sh" unlock-lte >/dev/null 2>&1
    else
        log_msg "[normal] carrier.sh 未找到, 跳过 unlock-lte" "[warn]"
    fi

    # 重置 WiFi/移动数据 settings
    se_del global low_power_mode
    se_del global low_power_sticky
    se_put global data_stall_alarm_aggressive 0
    se_put global data_stall_alarm_non_aggressive 0
    se_del global wifi_batched_scan_results_ms
    se_del global wifi_recovery_state
    se_put global mobile_data_preferred 1
    se_put global wifi_idle_ms "$WIFI_IDLE_MS"
    se_put global wifi_persistent_group_remove_delay_ms 30000

    # 清理 DNS 预热 PID
    rm -f "$DNS_PREFETCH_PID" 2>/dev/null

    # 重启 monitor.sh (如果配置启用)
    if [ "$ENABLE_MONITOR" = "true" ]; then
        if ! se_monitor_running; then
            sh "$MODDIR/scripts/monitor.sh" start >/dev/null 2>&1
        fi
    fi

    log_msg "已恢复默认优化模式" "[weaknet]"
    echo "[OK] 已恢复默认优化"
    echo "     - Data Saver 已关闭"
    echo "     - 5G 模式已恢复"
    echo "     - 调度器已恢复工作"
    return 0
}

# ----------------------------------------------------------------------
# 状态显示（保留 S1 + 修改点 4: 命名统一）
# ----------------------------------------------------------------------
show_status() {
    echo "=== 当前网络优化状态 ==="
    echo ""
    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        echo "  [!] weaknet 模式激活中（调度器已让位）"
        echo ""
    fi

    echo "[WiFi]"
    echo "  scan_throttle         : $(se_get global wifi_scan_throttle_enabled)"
    echo "  scan_interval_ms      : $(se_get global wifi_framework_scan_interval_ms)"
    echo "  suspend_optimizations : $(se_get global wifi_suspend_optimizations_enabled)"
    echo "  idle_ms               : $(se_get global wifi_idle_ms)"
    echo "  bad_rssi_threshold    : $(se_get global wifi_bad_rssi_threshold) dBm"
    echo ""

    echo "[移动网络]"
    echo "  mobile_data_always_on     : $(se_get global mobile_data_always_on)"
    echo "  mobile_data_preferred     : $(se_get global mobile_data_preferred)"
    echo "  mobile_data_auto_handover : $(se_get global mobile_data_auto_handover)"
    echo "  preferred_network_mode    : $(se_get global preferred_network_mode) (11=LTE only, 9=LTE/3G, 26/27/32/33=5G)"
    echo "  endc_capability           : $(se_get global endc_capability) (0=关闭ENDC)"
    echo ""

    echo "[Data Saver]"
    local ds_status
    ds_status=$(cmd netpolicy get restrict-background 2>/dev/null)
    if [ "$ds_status" = "1" ] || echo "$ds_status" | grep -qi "enabled\|true"; then
        echo "  restrict-background       : WARN 已启用 (后台数据受限)"
    else
        echo "  restrict-background       : OK 已禁用"
    fi
    echo ""

    echo "[5G 备份]"
    if [ -f "$SE_5G_BACKUP_FILE" ]; then
        echo "  备份的 PNM 值             : $(cat "$SE_5G_BACKUP_FILE" 2>/dev/null)"
    else
        echo "  备份的 PNM 值             : 无备份"
    fi
    echo ""

    echo "[实时网络]"
    echo "  WiFi RSSI : $(se_get_wifi_rssi) dBm"
    echo "  移动 dBm  : $(se_get_mobile_dbm)"
    echo "  NR RSRP   : $(se_get_nr_rsrp) dBm"
    echo "  NR SINR   : $(se_get_nr_sinr) dB"
    echo "  公网延迟  : $(se_get_ping_ms) ms"
    return 0
}

# ----------------------------------------------------------------------
# 修改点: 新增代理稳定模式（v1.1）
# ----------------------------------------------------------------------
apply_vpn_mode() {
    echo "=== 应用代理稳定模式 (v1.1) ==="
    silent_reset

    echo "  [..] 锁定 LTE only (防止 5G/4G 切换导致代理隧道断流)..."
    if [ -f "$MODDIR/scripts/carrier.sh" ]; then
        sh "$MODDIR/scripts/carrier.sh" lock-lte >/dev/null 2>&1
    else
        log_msg "[vpn] carrier.sh 未找到, 跳过 lock-lte" "[warn]"
    fi

    se_put global mobile_data_always_on 1
    echo "  [OK] mobile_data_always_on = 1 (移动数据保活)"

    echo "  [..] 开启 Data Saver (压制后台 App 抢占带宽)..."
    if cmd netpolicy set restrict-background true 2>/dev/null; then
        echo "  [OK] Data Saver 已开启"
        log_msg "[vpn] Data Saver 已开启 (restrict-background=true)" "[weaknet]"
    else
        echo "  [WARN] Data Saver 开启失败 (部分 ROM 不支持)"
        log_msg "[vpn] cmd netpolicy set restrict-background true 失败" "[warn]"
    fi

    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global volte_vt_enabled 1

    echo "  [OK] 代理稳定模式已应用 (锁定4G + 移动数据保活 + 后台压制)"

    dns_prefetch "vpn" \
        dns.alidns.com dot.pub \
        www.cloudflare.com www.google.com \
        api.cloudflare.com

    se_notify "网络增强 → 代理稳定模式" "已开启代理稳定模式\n锁定4G + 移动数据保活 + 禁后台抢网\n\n若代理软件断流, 请使用下方白名单工具将其加入白名单\n结束使用后请及时恢复默认 (菜单 5)"
    log_msg "[vpn] 代理稳定模式已应用" "[weaknet]"

    set_weaknet_active "vpn"
    echo "[OK] 代理稳定模式已生效"
    echo ""
    echo "  注意: 已锁定 LTE Only, 非 VoLTE 来电可能无法接通"
    echo "  代理使用结束请执行 '恢复默认优化' (菜单 5)"
    return 0
}

# ----------------------------------------------------------------------
# 修改点: 新增代理白名单管理小工具（v1.1）
# ----------------------------------------------------------------------
validate_package_name() {
    local pkg="$1"
    [ -z "$pkg" ] && return 1
    case "$pkg" in
        *[!a-zA-Z0-9._-]*) return 1 ;;
        *) ;;
    esac
    case "${pkg%%[!a-zA-Z]*}" in
        '') return 1 ;;
        *) return 0 ;;
    esac
}

validate_uid() {
    local uid="$1"
    [ -z "$uid" ] && return 1
    case "$uid" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

get_uid_by_package() {
    local pkg="$1"
    [ -z "$pkg" ] && return 1
    local pm_output
    pm_output=$(pm list packages -U "$pkg" 2>/dev/null | head -1)
    [ -z "$pm_output" ] && return 1
    local uid
    uid=$(echo "$pm_output" | grep -oE 'uid:[0-9]+' | cut -d: -f2)
    [ -z "$uid" ] && return 1
    validate_uid "$uid" || return 1
    echo "$uid"
    return 0
}

add_vpn_whitelist() {
    local pkg="$1"
    if [ -z "$pkg" ]; then
        echo "[FAIL] 未提供包名"
        echo "用法: sh weaknet.sh add-wl <包名>"
        return 1
    fi
    if ! validate_package_name "$pkg"; then
        echo "[FAIL] 包名格式非法: $pkg"
        echo "  包名仅允许字母/数字/点/下划线/连字符, 且必须以字母开头"
        log_msg "[vpn-wl] 包名格式非法: $pkg" "[warn]"
        return 1
    fi
    echo "=== 加入 Data Saver 白名单 ==="
    echo "  包名: $pkg"
    local uid
    uid=$(get_uid_by_package "$pkg")
    if [ -z "$uid" ]; then
        echo "  [FAIL] 无法获取 $pkg 的 UID"
        echo "  请确认包名正确, 且应用已安装"
        log_msg "[vpn-wl] 获取 UID 失败: $pkg" "[warn]"
        return 1
    fi
    if ! validate_uid "$uid"; then
        echo "  [FAIL] UID 格式非法: $uid (非纯数字)"
        log_msg "[vpn-wl] UID 格式非法: $pkg (UID=$uid)" "[warn]"
        return 1
    fi
    echo "  UID : $uid"
    if cmd netpolicy add restrict-background-whitelist "$uid" 2>/dev/null; then
        echo "  [OK] 已将 $pkg (UID=$uid) 加入后台流量白名单"
        se_notify "网络增强 → 白名单已添加" "已将 $pkg 加入后台流量白名单\nData Saver 不再限制该应用的后台流量"
        log_msg "[vpn-wl] 已加入白名单: $pkg (UID=$uid)" "[weaknet]"
        return 0
    else
        echo "  [FAIL] 添加白名单失败"
        log_msg "[vpn-wl] 添加白名单失败: $pkg (UID=$uid)" "[warn]"
        return 1
    fi
}

remove_vpn_whitelist() {
    local pkg="$1"
    if [ -z "$pkg" ]; then
        echo "[FAIL] 未提供包名"
        echo "用法: sh weaknet.sh rm-wl <包名>"
        return 1
    fi
    if ! validate_package_name "$pkg"; then
        echo "[FAIL] 包名格式非法: $pkg"
        echo "  包名仅允许字母/数字/点/下划线/连字符, 且必须以字母开头"
        log_msg "[vpn-wl] 包名格式非法: $pkg" "[warn]"
        return 1
    fi
    echo "=== 移出 Data Saver 白名单 ==="
    echo "  包名: $pkg"
    local uid
    uid=$(get_uid_by_package "$pkg")
    if [ -z "$uid" ]; then
        echo "  [FAIL] 无法获取 $pkg 的 UID"
        echo "  请确认包名正确, 且应用已安装"
        log_msg "[vpn-wl] 获取 UID 失败: $pkg" "[warn]"
        return 1
    fi
    if ! validate_uid "$uid"; then
        echo "  [FAIL] UID 格式非法: $uid (非纯数字)"
        log_msg "[vpn-wl] UID 格式非法: $pkg (UID=$uid)" "[warn]"
        return 1
    fi
    echo "  UID : $uid"
    if cmd netpolicy remove restrict-background-whitelist "$uid" 2>/dev/null; then
        echo "  [OK] 已将 $pkg (UID=$uid) 移出后台流量白名单"
        se_notify "网络增强 → 白名单已移除" "已将 $pkg 移出后台流量白名单\n该应用的后台流量将受 Data Saver 限制"
        log_msg "[vpn-wl] 已移出白名单: $pkg (UID=$uid)" "[weaknet]"
        return 0
    else
        echo "  [FAIL] 移出白名单失败"
        log_msg "[vpn-wl] 移出白名单失败: $pkg (UID=$uid)" "[warn]"
        return 1
    fi
}

list_vpn_whitelist() {
    echo "=== 当前 Data Saver 白名单 ==="
    echo ""
    local wl_output
    wl_output=$(cmd netpolicy list restrict-background-whitelist 2>/dev/null)
    local wl_ret=$?
    if [ $wl_ret -ne 0 ] || [ -z "$wl_output" ]; then
        echo "[FAIL] 获取白名单失败 (部分ROM不支持, 或白名单为空)"
        return 1
    fi
    echo "$wl_output"
    return 0
}

case "$1" in
    video)        apply_video_mode ;;
    game)         apply_game_mode ;;
    social)       apply_social_mode ;;
    download)     apply_download_mode ;;
    vpn)          apply_vpn_mode ;;
    add-wl)       add_vpn_whitelist "$2" ;;
    rm-wl)        remove_vpn_whitelist "$2" ;;
    list-wl)      list_vpn_whitelist ;;
    normal|default) apply_normal_mode ;;
    status)       show_status ;;
    *)
        echo "弱网自救工具 v${SE_VERSION}"
        echo ""
        echo "用法: sh weaknet.sh <模式>"
        echo ""
        echo "可选模式:"
        echo "  video     视频模式 (弱网预加载优化)"
        echo "  game      游戏模式 (锁定 LTE only + 禁后台带宽)"
        echo "            注意: LTE Only 下非 VoLTE 来电可能无法接通"
        echo "  social    社交模式 (保 WiFi, DNS 预热微信/QQ)"
        echo "  download  下载模式 (高带宽持续传输)"
        echo "  normal    恢复默认优化 (关闭 Data Saver + 恢复 5G + 重启调度器)"
        echo "  status    查看当前状态"
        ;;
esac
exit 0
