#!/system/bin/sh
# monitor.sh — 网络增强 v1.0 动态自适应调度器

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
# 防振荡参数默认值（从 config.sh 读取）
# ----------------------------------------------------------------------
: "${DOWNGRADE_COOLDOWN_SEC:=1800}"      # 降级冷却 30 分钟
: "${DEGRADE_RECOVERY_COUNT:=3}"        # 连续 3 次正常才恢复 5G
: "${DEGRADE_NO_NET_ROLLBACK_COUNT:=2}" # 连续 2 次无网络回退

# ----------------------------------------------------------------------
# 等级显示名
# ----------------------------------------------------------------------
get_level_display_name() {
    case "$1" in
        strong)    echo "强信号 (省电)" ;;
        normal)    echo "正常" ;;
        weak)      echo "弱信号自救" ;;
        critical)  echo "极限自救" ;;
        no_network) echo "无网络" ;;
        *)         echo "未知" ;;
    esac
}

get_level_description() {
    case "$1" in
        strong)    echo "允许休眠+扫描慢+省电" ;;
        normal)    echo "标准优化+扫描中" ;;
        weak)      echo "极限容忍+移动数据兜底" ;;
        critical)  echo "全力保活+扫描激进+ping反馈" ;;
        no_network) echo "等待网络恢复" ;;
        *)         echo "" ;;
    esac
}

# ----------------------------------------------------------------------
# 4 级综合判定（含 SINR 维度）
# ----------------------------------------------------------------------
#   strong:  RSSI ≥ -60 且 Ping < 80ms 且 SINR ≥ 10
#   normal:  RSSI -60~-75 或 Ping 80~150ms
#   weak:    RSSI -75~-90 或 Ping 150~200ms
#   critical: RSSI < -90 或 Ping > 200ms 或 SINR < 0
compute_overall_level_v2() {
    local net_type="$1" wifi_rssi="$2" mobile_dbm="$3" ping_ms="$4"
    local nr_sinr="${5:-}"

    # 无网络时直接返回
    if [ -z "$net_type" ] || [ "$net_type" = "none" ]; then
        echo "no_network"
        return 0
    fi

    local wifi_lvl="unknown"
    local mobile_lvl="unknown"

    # WiFi 等级计算
    if [ -n "$wifi_rssi" ] && [ "$wifi_rssi" != "?" ]; then
        local abs_r=""
        if [ "$wifi_rssi" -lt 0 ] 2>/dev/null; then
            abs_r=$((-wifi_rssi))
        elif [ "$wifi_rssi" -gt 0 ] 2>/dev/null; then
            abs_r="$wifi_rssi"
        fi
        if [ -n "$abs_r" ] && [ "$abs_r" -gt 0 ] 2>/dev/null; then
            if [ "$abs_r" -lt "$WIFI_STRONG_RSSI" ] 2>/dev/null; then
                wifi_lvl="strong"
            elif [ "$abs_r" -lt "$WIFI_WEAK_RSSI" ] 2>/dev/null; then
                wifi_lvl="normal"
            else
                wifi_lvl="weak"
            fi
        fi
    fi

    # 移动等级计算
    local mlevel=""
    mlevel=$(se_get_mobile_level 2>/dev/null)
    if [ -n "$mlevel" ]; then
        case "$mlevel" in
            4)         mobile_lvl="strong" ;;
            2|3)       mobile_lvl="normal" ;;
            0|1)       mobile_lvl="weak" ;;
            *)         mobile_lvl="normal" ;;
        esac
    elif [ -n "$mobile_dbm" ] && [ "$mobile_dbm" != "?" ] && [ "$mobile_dbm" != "" ]; then
        local abs_d=""
        if [ "$mobile_dbm" -lt 0 ] 2>/dev/null; then
            abs_d=$((-mobile_dbm))
        elif [ "$mobile_dbm" -gt 0 ] 2>/dev/null; then
            abs_d="$mobile_dbm"
        fi
        if [ -n "$abs_d" ] && [ "$abs_d" -gt 0 ] 2>/dev/null; then
            if [ "$abs_d" -lt "$MOBILE_STRONG_DBM" ] 2>/dev/null; then
                mobile_lvl="strong"
            elif [ "$abs_d" -le "$MOBILE_WEAK_DBM" ] 2>/dev/null; then
                mobile_lvl="normal"
            else
                mobile_lvl="weak"
            fi
        fi
    fi

    # 基础等级判定
    local base_level="normal"
    case "$net_type" in
        wifi)
            case "$wifi_lvl" in
                strong|normal|weak) base_level="$wifi_lvl" ;;
                *)                  base_level="normal" ;;
            esac
            ;;
        mobile)
            case "$mobile_lvl" in
                strong|normal|weak) base_level="$mobile_lvl" ;;
                *)                  base_level="normal" ;;
            esac
            ;;
        dual)
            if [ "$wifi_lvl" = "weak" ] || [ "$mobile_lvl" = "weak" ]; then
                base_level="weak"
            elif [ "$wifi_lvl" = "strong" ] && [ "$mobile_lvl" = "strong" ]; then
                base_level="strong"
            else
                base_level="normal"
            fi
            ;;
        *)      base_level="normal" ;;
    esac

    # SINR 维度判定（S3 新增）
    local sinr_critical=0
    if [ -n "$nr_sinr" ] && [ "$nr_sinr" != "?" ]; then
        case "$nr_sinr" in
            ''|*[!0-9-]*) ;;
            *)
                if [ "$nr_sinr" -lt 0 ] 2>/dev/null; then
                    sinr_critical=1
                fi
                ;;
        esac
    fi

    # ping 反馈调节
    local ping_critical=0 ping_bad=0
    if [ "$ENABLE_PING_FEEDBACK" = "true" ] && [ "$ping_ms" != "?" ] && [ -n "$ping_ms" ]; then
        case "$ping_ms" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$ping_ms" -ge "$PING_BAD_MS" ] 2>/dev/null; then
                    ping_critical=1
                elif [ "$ping_ms" -ge "$PING_GOOD_MS" ] 2>/dev/null && [ "$ping_ms" -lt "$PING_BAD_MS" ] 2>/dev/null; then
                    ping_bad=1
                fi
                ;;
        esac
    fi

    # SINR < 0 直接降级到 critical（S3）
    if [ "$sinr_critical" = "1" ]; then
        echo "critical"
        return 0
    fi

    if [ "$ping_critical" = "1" ]; then
        if [ "$base_level" = "weak" ]; then
            echo "critical"
        else
            echo "weak"
        fi
        return 0
    fi
    if [ "$ping_bad" = "1" ] && [ "$base_level" = "strong" ]; then
        echo "normal"
        return 0
    fi
    echo "$base_level"
    return 0
}

# ----------------------------------------------------------------------
# 动态参数应用（间隔统一由 config.sh MONITOR_NORMAL_INTERVAL 控制）
# ----------------------------------------------------------------------
apply_dynamic_params() {
    local level="$1"
    local rssi_abs="$2"

    case "$level" in
        strong|normal|weak|critical|no_network) ;;
        *) level="normal" ;;
    esac

    case "$level" in
        strong|normal)
            se_put global data_stall_alarm_aggressive 0
            se_put global data_stall_alarm_non_aggressive 0
            se_del global enable_nr_dc
            se_del global endc_capability
            se_del global nr_handover_enabled
            se_del global vonr_enabled
            ;;
        weak)
            se_put global data_stall_alarm_non_aggressive 0
            ;;
    esac

    local params interval scan_ms bad_rssi mobile_ka ping_chk
    params=$(se_compute_dynamic_params "$level" "$rssi_abs" 2>/dev/null)
    [ -z "$params" ] && params="120 15000 -88 1 1"
    interval=$(echo "$params" | awk '{print $1}')
    scan_ms=$(echo "$params" | awk '{print $2}')
    bad_rssi=$(echo "$params" | awk '{print $3}')
    mobile_ka=$(echo "$params" | awk '{print $4}')
    ping_chk=$(echo "$params" | awk '{print $5}')
    [ -z "$interval" ] && interval=120
    [ -z "$scan_ms" ] && scan_ms=15000
    [ -z "$bad_rssi" ] && bad_rssi=-88

    case "$level" in
        strong)
            se_put global wifi_suspend_optimizations_enabled 1
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            ;;
        normal)
            se_put global wifi_suspend_optimizations_enabled 0
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            se_put global mobile_data_always_on "$mobile_ka"
            ;;
        weak)
            se_put global wifi_suspend_optimizations_enabled 0
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            se_put global mobile_data_always_on 1
            se_put global mobile_data_preferred 1
            se_put global mobile_data_auto_handover 1
            se_put global data_stall_alarm_aggressive 1
            ;;
        critical)
            se_put global wifi_suspend_optimizations_enabled 0
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            se_put global mobile_data_always_on 1
            se_put global mobile_data_preferred 1
            se_put global mobile_data_auto_handover 1
            se_put global data_stall_alarm_aggressive 1
            se_put global data_stall_alarm_non_aggressive 1
            se_put global enable_nr_dc 1
            se_put global endc_capability 1
            se_put global nr_handover_enabled 1
            se_put global volte_vt_enabled 1
            se_put global vonr_enabled 1
            ;;
        no_network)
            :
            ;;
    esac

    [ -z "$interval" ] && interval=120
    [ -z "$scan_ms" ] && scan_ms=15000
    [ -z "$bad_rssi" ] && bad_rssi=-88
    echo "${interval} ${scan_ms} ${bad_rssi}"
    return 0
}

# ----------------------------------------------------------------------
# 状态文件写入
# ----------------------------------------------------------------------
write_state() {
    local net_type="$1"
    local level="$2"
    local rssi="$3"
    local dbm="$4"
    local ping_ms="$5"
    local params="$6"
    local nr_rsrp="${7:-}"
    local nr_sinr="${8:-}"
    local fake_5g_active="${9:-0}"
    cat > "${SE_STATE_FILE}.tmp" <<EOF
PID=$$
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NET_TYPE=$net_type
LEVEL=$level
WIFI_RSSI=$rssi
MOBILE_DBM=$dbm
PING_MS=$ping_ms
PARAMS=$params
NR_RSRP=$nr_rsrp
NR_SINR=$nr_sinr
FAKE_5G_ACTIVE=$fake_5g_active
EOF
    mv "${SE_STATE_FILE}.tmp" "$SE_STATE_FILE" 2>/dev/null
    return 0
}

# ----------------------------------------------------------------------
# 通知发送
# ----------------------------------------------------------------------
send_switch_notification() {
    [ "$ENABLE_SWITCH_NOTIFY" = "true" ] || return 0
    local level="$1" rssi="$2" dbm="$3" ping_ms="$4" net_type="$5"
    local display_name desc
    display_name=$(get_level_display_name "$level")
    desc=$(get_level_description "$level")

    if [ -z "$ping_ms" ] || [ "$ping_ms" = "?" ]; then
        ping_ms=$(se_get_ping_ms 2>/dev/null)
        [ -z "$ping_ms" ] && ping_ms="?"
    fi

    local title="网络增强 → ${display_name}"
    local body="策略: ${desc}
网络: ${net_type:-unknown}
延迟: ${ping_ms} ms"
    se_notify "$title" "$body"
    log_msg "[通知] $title | ping=${ping_ms}ms" "[monitor]"
    return 0
}

# ----------------------------------------------------------------------
# 5G 假满格降级处理（含防振荡冷却 + 无网络回退）
# ----------------------------------------------------------------------
# 全局变量:
#   FAKE_5G_ACTIVE       = 0/1 是否处于降级状态
#   DOWNGRADE_TIMESTAMP  = 降级时的 epoch 时间戳
#   RECOVERY_COUNT       = 连续正常次数
#   NO_NET_FAIL_COUNT    = 降级后无网络连续失败次数
# 防振荡: 降级后冷却期内不恢复 5G
# 隔离: weaknet 激活时跳过
handle_fake_5g() {
    [ "$ENABLE_FAKE_5G_DETECTION" = "true" ] || return 0

    # weaknet 激活时绝对禁止任何操作
    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        return 0
    fi

    # PNM 受限品牌跳过（避免反复无效尝试）
    if se_is_pnm_restricted; then
        return 0
    fi

    if se_detect_fake_5g; then
        # 检测到假满格
        if [ -z "$FAKE_5G_ACTIVE" ] || [ "$FAKE_5G_ACTIVE" = "0" ]; then
            # 首次触发，立即降级
            log_msg "[5G降级] 触发假满格, 调用 carrier.sh degrade" "[5g]"

            # 调用 carrier.sh 的 degrade_5g_to_4g 函数
            if [ -f "$MODDIR/scripts/carrier.sh" ]; then
                sh "$MODDIR/scripts/carrier.sh" degrade >/dev/null 2>&1
            fi

            FAKE_5G_ACTIVE=1
            RECOVERY_COUNT=0
            NO_NET_FAIL_COUNT=0
            DOWNGRADE_TIMESTAMP=$(date +%s 2>/dev/null || echo 0)

            se_notify "网络增强 → 5G假满格降级" "检测到5G信号良好但实际网络差\n已自动降级到4G\n冷却期内不会恢复5G"
            log_msg "[5G降级] 已降级到 4G, 冷却 ${DOWNGRADE_COOLDOWN_SEC}s 内不恢复" "[5g]"
        else
            # 已处于降级状态, 记录日志
            log_msg "[5G降级] 仍处于假满格降级状态 (持续中)" "[5g]"
        fi
    else
        # 5G 正常
        if [ "$FAKE_5G_ACTIVE" = "1" ]; then
            # 防振荡冷却检查: 冷却期内不恢复 5G, 避免频繁切换
            local now elapsed
            now=$(date +%s 2>/dev/null || echo 0)
            elapsed=$((now - DOWNGRADE_TIMESTAMP))

            if [ "$elapsed" -lt "$DOWNGRADE_COOLDOWN_SEC" ]; then
                # 冷却期内, 不恢复
                local remaining=$((DOWNGRADE_COOLDOWN_SEC - elapsed))
                if [ $((loop_count % 5)) -eq 0 ]; then
                    log_msg "[5G冷却] 降级 ${elapsed}s, 还需 ${remaining}s 才允许恢复" "[5g]"
                fi
                return 0
            fi

            # 冷却期已过, 开始计数恢复
            RECOVERY_COUNT=$((RECOVERY_COUNT + 1))
            log_msg "[5G恢复] 检测正常 ($RECOVERY_COUNT/$DEGRADE_RECOVERY_COUNT)" "[5g]"

            if [ "$RECOVERY_COUNT" -ge "$DEGRADE_RECOVERY_COUNT" ]; then
                # 连续 N 次正常, 恢复 5G
                log_msg "[5G恢复] 连续${DEGRADE_RECOVERY_COUNT}次正常, 调用 carrier.sh unlock-lte" "[5g]"

                if [ -f "$MODDIR/scripts/carrier.sh" ]; then
                    sh "$MODDIR/scripts/carrier.sh" unlock-lte >/dev/null 2>&1
                fi

                FAKE_5G_ACTIVE=0
                RECOVERY_COUNT=0
                NO_NET_FAIL_COUNT=0
                DOWNGRADE_TIMESTAMP=0
                se_notify "网络增强 → 5G已恢复" "网络质量已稳定\n已自动切回5G模式"
            fi
        fi
    fi
}

# ----------------------------------------------------------------------
# 无网络回退策略 — 降级到 4G 后 Ping 连续失败则恢复 5G, 避免死锁
# ----------------------------------------------------------------------
# weaknet 激活时绝对禁止
handle_no_network_rollback() {
    # weaknet 激活时绝对禁止
    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        return 0
    fi

    # 仅在 5G 降级状态下检查
    [ "$FAKE_5G_ACTIVE" = "1" ] || return 0

    # PNM 受限品牌跳过
    se_is_pnm_restricted && return 0

    local ping_ms="$1"
    local net_type="$2"

    # Ping 完全失败（值为 "?"）或网络类型为 none
    if [ "$ping_ms" = "?" ] || [ "$net_type" = "none" ]; then
        NO_NET_FAIL_COUNT=$((NO_NET_FAIL_COUNT + 1))
        log_msg "[无网回退] 4G 降级后 Ping 失败 ($NO_NET_FAIL_COUNT/$DEGRADE_NO_NET_ROLLBACK_COUNT)" "[5g]"

        if [ "$NO_NET_FAIL_COUNT" -ge "$DEGRADE_NO_NET_ROLLBACK_COUNT" ]; then
            # 连续 N 次无网络, 恢复 5G
            log_msg "[无网回退] 4G 无改善, 自动恢复 5G (避免死锁)" "[5g]"

            if [ -f "$MODDIR/scripts/carrier.sh" ]; then
                sh "$MODDIR/scripts/carrier.sh" unlock-lte >/dev/null 2>&1
            fi

            FAKE_5G_ACTIVE=0
            RECOVERY_COUNT=0
            NO_NET_FAIL_COUNT=0
            DOWNGRADE_TIMESTAMP=0
            se_notify "网络增强 → 4G无改善已恢复5G" "降级到4G后网络仍不通\n已尝试恢复5G模式"
        fi
    else
        # 网络正常, 重置失败计数
        if [ "$NO_NET_FAIL_COUNT" -gt 0 ]; then
            NO_NET_FAIL_COUNT=0
            log_msg "[无网回退] 网络恢复, 重置失败计数" "[5g]"
        fi
    fi
    return 0
}

# ----------------------------------------------------------------------
# 主循环（每 $MONITOR_NORMAL_INTERVAL 秒检测一次）
# ----------------------------------------------------------------------
# weaknet 激活时跳过本轮; 5G 假满格降级 + 无网络回退 均在内部处理
run_monitor_loop() {
    local current_level="init"
    local loop_count=0
    FAKE_5G_ACTIVE=0
    RECOVERY_COUNT=0
    NO_NET_FAIL_COUNT=0
    DOWNGRADE_TIMESTAMP=0

    trap 'rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null; log_msg "调度器退出 (信号)" "[monitor]"; exit 0' INT TERM
    trap 'rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null; log_msg "调度器退出 (EXIT)" "[monitor]"' EXIT

    echo $$ > "$SE_PID_FILE" 2>/dev/null

    log_msg "调度器启动 v${SE_VERSION} (PID=$$)" "[monitor]"
    log_msg "间隔=${MONITOR_NORMAL_INTERVAL}s | ping反馈=${ENABLE_PING_FEEDBACK} | OEM兼容=${ENABLE_OEM_COMPAT} | 假满格检测=${ENABLE_FAKE_5G_DETECTION}" "[monitor]"
    log_msg "防振荡: 冷却=${DOWNGRADE_COOLDOWN_SEC}s 恢复需连续${DEGRADE_RECOVERY_COUNT}次 无网回退${DEGRADE_NO_NET_ROLLBACK_COUNT}次" "[monitor]"
    write_state "init" "init" "?" "?" "?" "0 0 0" "" "" 0

    # 首轮立即检测一次
    sleep 2
    local _net_type _wifi_rssi _mobile_dbm _ping_ms _nr_rsrp _nr_sinr _target_level _rssi_abs _applied_params
    _net_type=$(se_detect_network_type 2>/dev/null)
    _wifi_rssi=$(se_get_wifi_rssi 2>/dev/null)
    _mobile_dbm=$(se_get_mobile_dbm 2>/dev/null)
    _ping_ms=$(se_get_ping_ms 2>/dev/null)
    _nr_rsrp=$(se_get_nr_rsrp 2>/dev/null)
    _nr_sinr=$(se_get_nr_sinr 2>/dev/null)
    [ -z "$_net_type" ] && _net_type="none"
    [ -z "$_ping_ms" ] && _ping_ms="?"

    _target_level=$(compute_overall_level_v2 "$_net_type" "$_wifi_rssi" "$_mobile_dbm" "$_ping_ms" "$_nr_sinr" 2>/dev/null)
    [ -z "$_target_level" ] && _target_level="normal"

    _rssi_abs=0
    if [ -n "$_wifi_rssi" ] && [ "$_wifi_rssi" != "?" ]; then
        case "$_wifi_rssi" in
            ''|*[!0-9-]*) ;;
            *)
                if [ "$_wifi_rssi" -lt 0 ] 2>/dev/null; then
                    _rssi_abs=$((-_wifi_rssi))
                elif [ "$_wifi_rssi" -gt 0 ] 2>/dev/null; then
                    _rssi_abs="$_wifi_rssi"
                fi
                ;;
        esac
    fi

    _applied_params=$(se_compute_dynamic_params "$_target_level" "$_rssi_abs" 2>/dev/null)
    [ -z "$_applied_params" ] && _applied_params="120 15000 -88 1 1"

    current_level="$_target_level"
    write_state "$_net_type" "$_target_level" "${_wifi_rssi:-?}" "${_mobile_dbm:-无}" "$_ping_ms" "$_applied_params" "${_nr_rsrp:-?}" "${_nr_sinr:-?}" 0
    log_msg "[首轮] 等级=$current_level net=$_net_type rssi=$_wifi_rssi dbm=$_mobile_dbm ping=${_ping_ms}ms rsrp=$_nr_rsrp sinr=$_nr_sinr" "[monitor]"

    # settings 写入放后台
    apply_dynamic_params "$_target_level" "$_rssi_abs" >/dev/null 2>&1 &

    while true; do
        loop_count=$((loop_count + 1))

        # weaknet 激活时跳过本轮, 禁止任何降级/升级/无网络回退操作
        if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
            if [ $((loop_count % 5)) -eq 0 ]; then
                log_msg "[让位] weaknet 激活, 跳过本轮 (loop #$loop_count), 不执行任何 PNM 操作" "[monitor]"
            fi
            sleep "$MONITOR_NORMAL_INTERVAL" 2>/dev/null
            continue
        fi

        # 网络检测
        local net_type wifi_rssi mobile_dbm ping_ms nr_rsrp nr_sinr
        net_type=$(se_detect_network_type 2>/dev/null)
        wifi_rssi=$(se_get_wifi_rssi 2>/dev/null)
        mobile_dbm=$(se_get_mobile_dbm 2>/dev/null)
        ping_ms=$(se_get_ping_ms 2>/dev/null)
        nr_rsrp=$(se_get_nr_rsrp 2>/dev/null)
        nr_sinr=$(se_get_nr_sinr 2>/dev/null)

        [ -z "$net_type" ] && net_type="none"
        [ -z "$ping_ms" ] && ping_ms="?"

        # 4 级综合判定（含 SINR 维度）
        local target_level
        target_level=$(compute_overall_level_v2 "$net_type" "$wifi_rssi" "$mobile_dbm" "$ping_ms" "$nr_sinr" 2>/dev/null)
        [ -z "$target_level" ] && target_level="normal"

        local rssi_abs=0
        if [ -n "$wifi_rssi" ] && [ "$wifi_rssi" != "?" ]; then
            case "$wifi_rssi" in
                ''|*[!0-9-]*) ;;
                *)
                    if [ "$wifi_rssi" -lt 0 ] 2>/dev/null; then
                        rssi_abs=$((-wifi_rssi))
                    elif [ "$wifi_rssi" -gt 0 ] 2>/dev/null; then
                        rssi_abs="$wifi_rssi"
                    fi
                    ;;
            esac
        fi

        # 无网络回退检查（降级后 Ping 彻底不通则恢复 5G, 避免死锁）
        handle_no_network_rollback "$ping_ms" "$net_type"

        # 5G 假满格降级处理（含防振荡冷却）
        handle_fake_5g

        # 等级切换处理
        if [ "$target_level" != "$current_level" ]; then
            log_msg "[切换] $current_level → $target_level | net=$net_type rssi=$wifi_rssi dbm=$mobile_dbm ping=${ping_ms}ms sinr=$nr_sinr" "[monitor]"

            local applied_params
            applied_params=$(se_compute_dynamic_params "$target_level" "$rssi_abs" 2>/dev/null)
            [ -z "$applied_params" ] && applied_params="120 15000 -88 1 1"

            current_level="$target_level"
            write_state "$net_type" "$target_level" "${wifi_rssi:-?}" "${mobile_dbm:-无}" "$ping_ms" "$applied_params" "${nr_rsrp:-?}" "${nr_sinr:-?}" "$FAKE_5G_ACTIVE"
            send_switch_notification "$current_level" "${wifi_rssi:-?}" "${mobile_dbm:-无}" "$ping_ms" "$net_type"

            # settings 写入放后台
            apply_dynamic_params "$target_level" "$rssi_abs" >/dev/null 2>&1 &
        fi

        # 所有等级统一使用 MONITOR_NORMAL_INTERVAL（移除原按等级区分间隔的逻辑）
        local next_interval="$MONITOR_NORMAL_INTERVAL"

        # 每 5 轮记录一次监控日志（约 10 分钟一次）
        if [ $((loop_count % 5)) -eq 0 ]; then
            log_msg "[监控#$loop_count] 等级=$current_level net=$net_type rssi=$wifi_rssi dbm=$mobile_dbm ping=${ping_ms}ms rsrp=$nr_rsrp sinr=$nr_sinr fake5g=$FAKE_5G_ACTIVE" "[monitor]"
        fi

        sleep "$next_interval" 2>/dev/null
    done
}

# ----------------------------------------------------------------------
# 启动/停止/状态管理
# ----------------------------------------------------------------------
start_monitor() {
    [ "$ENABLE_MONITOR" = "true" ] || {
        echo "智能调度器已禁用 (ENABLE_MONITOR=false)"
        return 0
    }

    if se_monitor_running; then
        echo "[INFO] 调度器已在运行 (PID=$(se_monitor_pid))"
        return 0
    fi

    rm -f "$SE_PID_FILE" 2>/dev/null

    if command -v nohup >/dev/null 2>&1; then
        nohup sh "$0" _loop >/dev/null 2>&1 &
    else
        sh "$0" _loop >/dev/null 2>&1 &
    fi
    local new_pid=$!
    echo "$new_pid" > "$SE_PID_FILE" 2>/dev/null

    local tried=0
    while [ "$tried" -lt 5 ]; do
        [ -f "$SE_STATE_FILE" ] && break
        sleep 1
        tried=$((tried + 1))
    done

    if [ -f "$SE_STATE_FILE" ]; then
        echo "[OK] 智能调度器已启动 (PID=$new_pid)"
    else
        echo "[WARN] 调度器启动可能失败，请查看日志: $SE_LOG_FILE"
    fi
    log_msg "调度器启动请求 (PID=$new_pid)" "[monitor]"
    return 0
}

stop_monitor() {
    if ! [ -f "$SE_PID_FILE" ]; then
        echo "[INFO] 调度器未运行"
        return 0
    fi

    local pid
    pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    if [ -z "$pid" ]; then
        rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
        echo "[INFO] PID 文件为空，已清理"
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "[INFO] 进程 $pid 已不存在"
        rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
        return 0
    fi

    if [ -r "/proc/$pid/cmdline" ]; then
        if ! tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "monitor.sh"; then
            echo "[WARN] PID $pid 不是调度器进程，跳过 kill"
            rm -f "$SE_PID_FILE" 2>/dev/null
            return 1
        fi
    fi

    kill "$pid" 2>/dev/null
    local waited=0
    while [ "$waited" -lt 5 ]; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
        waited=$((waited + 1))
    done
    kill -9 "$pid" 2>/dev/null

    echo "[OK] 调度器已停止 (PID=$pid)"
    log_msg "调度器停止 (PID=$pid)" "[monitor]"
    rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
    return 0
}

show_status() {
    echo "=== 智能调度器状态 v${SE_VERSION} ==="

    if ! [ -f "$SE_PID_FILE" ]; then
        echo "  状态: 未运行"
        return 0
    fi

    local pid
    pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        echo "  状态: 进程已退出"
        rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
        return 0
    fi

    echo "  状态    : 运行中"
    echo "  PID     : $pid"

    if [ -f "$SE_STATE_FILE" ]; then
        echo ""
        echo "  最近状态:"
        while IFS='=' read -r key value; do
            case "$key" in
                PID)        echo "  PID          : $value" ;;
                TIMESTAMP)  echo "  更新时间     : $value" ;;
                NET_TYPE)   echo "  网络类型     : $value" ;;
                LEVEL)      echo "  当前等级     : $value ($(get_level_display_name "$value"))" ;;
                WIFI_RSSI)  echo "  WiFi RSSI    : $value dBm" ;;
                MOBILE_DBM) echo "  移动 dBm     : $value" ;;
                PING_MS)    echo "  公网延迟     : $value ms" ;;
                PARAMS)     echo "  动态参数     : $value" ;;
                NR_RSRP)    echo "  NR RSRP      : $value dBm" ;;
                NR_SINR)    echo "  NR SINR      : $value dB" ;;
                FAKE_5G_ACTIVE) echo "  5G假满格降级 : $([ "$value" = "1" ] && echo "是(已降级到4G)" || echo "否")" ;;
            esac
        done < "$SE_STATE_FILE"
    fi

    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        echo ""
        echo "  [!] weaknet 模式激活中，调度器已让位（禁止任何 PNM 操作）"
    fi
    return 0
}

detect_once() {
    echo "=== 单次网络检测 (v${SE_VERSION}) ==="
    local net_type wifi_rssi mobile_dbm ping_ms nr_rsrp nr_sinr nr_rsrq
    net_type=$(se_detect_network_type)
    wifi_rssi=$(se_get_wifi_rssi)
    mobile_dbm=$(se_get_mobile_dbm)
    ping_ms=$(se_get_ping_ms)
    nr_rsrp=$(se_get_nr_rsrp)
    nr_sinr=$(se_get_nr_sinr)
    nr_rsrq=$(se_get_nr_rsrq)

    local target_level
    target_level=$(compute_overall_level_v2 "$net_type" "$wifi_rssi" "$mobile_dbm" "$ping_ms" "$nr_sinr")

    echo "  网络类型     : $net_type"
    echo "  WiFi RSSI    : ${wifi_rssi:-未连接} dBm"
    echo "  移动 dBm     : ${mobile_dbm:-未检测}"
    echo "  NR RSRP      : ${nr_rsrp:-未检测} dBm"
    echo "  NR RSRQ      : ${nr_rsrq:-未检测} dB"
    echo "  NR SINR      : ${nr_sinr:-未检测} dB"
    echo "  公网延迟     : ${ping_ms} ms"
    echo "  综合等级     : $target_level ($(get_level_display_name "$target_level"))"
    echo ""

    # 5G 假满格判定
    if se_detect_fake_5g; then
        echo "  5G假满格判定 : WARN 检测到假满格"
    else
        echo "  5G假满格判定 : OK 正常"
    fi

    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        echo ""
        echo "  [!] weaknet 模式激活中, 调度器会跳过参数应用"
    fi

    if se_is_pnm_restricted; then
        echo "  [!] 当前品牌(${SE_BRAND:-?}) PNM 已标记受限, 5G 假满格降级功能不可用"
    fi
    return 0
}

case "$1" in
    start)   start_monitor ;;
    stop)    stop_monitor ;;
    restart)
        stop_monitor
        local_wait=0
        while se_monitor_running && [ "$local_wait" -lt 5 ]; do
            sleep 1
            local_wait=$((local_wait + 1))
        done
        start_monitor
        ;;
    status)  show_status ;;
    detect)  detect_once ;;
    notify)
        arg_level="${2:-normal}"
        send_switch_notification "$arg_level" "?" "?" "?" "wifi"
        echo "[OK] 通知已发送 (等级=$arg_level)"
        ;;
    cancel)
        se_notify_cancel
        echo "[OK] 已撤销调度器通知"
        ;;
    _loop)   run_monitor_loop ;;
    *)
        echo "网络增强动态自适应调度器 v${SE_VERSION}"
        echo ""
        echo "用法: sh monitor.sh <命令>"
        echo "命令: start | stop | restart | status | detect | notify | cancel"
        echo ""
        echo "特性:"
        echo "  - 检测间隔统一 ${MONITOR_NORMAL_INTERVAL}s"
        echo "  - 5G 假满格自动降级 (冷却 ${DOWNGRADE_COOLDOWN_SEC}s)"
        echo "  - 4 级判定含 SINR 维度"
        echo "  - weaknet 激活时严格隔离"
        ;;
esac
exit 0
