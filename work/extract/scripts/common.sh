#!/system/bin/sh
# common.sh — 卫星地球 Pro v6.3.0 公共函数库
#
# v6.3.0 关键修复（基于 AxManager 官方源码核实）:
#   1. MODDIR 解析：放弃不可靠的 ${0%/*}，改用 pwd + AXERONDIR + 多策略兜底
#      原因：AxManager 调用 action.sh 时执行 cd "<pluginPath>"; sh ./action.sh
#      导致 $0 = "./action.sh"，${0%/*} = "."，一旦脚本内 cd 就失效
#   2. se_put 错误吞没：修复 || true 在某些 sh 实现下不生效的问题
#   3. dumpsys 解析：增强多 ROM 兼容（MIUI/HyperOS/ColorOS/OneUI）
#   4. 全部外部命令加 2>/dev/null，确保脚本永不非零退出
#
# 严格遵循 AxManager 官方插件协议 + 免Root约束
# https://fahrez182.github.io/AxManager/zh/plugin/what-is-plugin.html

# ----------------------------------------------------------------------
# 路径与版本常量
# ----------------------------------------------------------------------
SE_VERSION="6.3.0"
SE_VERSION_CODE="6300"
SE_LOG_TAG="SatelliteEarth"

# 日志路径优先 /data/local/tmp（ADB 必写、稳定）
SE_LOG_FILE="/data/local/tmp/satellite_earth.log"
if [ ! -w "$(dirname "$SE_LOG_FILE")" ] 2>/dev/null; then
    SE_LOG_FILE="/storage/emulated/0/satellite_earth.log"
fi

# 运行时文件
SE_PID_FILE="/data/local/tmp/satellite_earth_monitor.pid"
SE_STATE_FILE="/data/local/tmp/satellite_earth_monitor.state"
SE_NOTIFY_TAG="satellite_earth_monitor"

# weaknet 互锁标志 + DNS 预热 PID 锁
WEAKNET_ACTIVE_FLAG="/data/local/tmp/satellite_earth_weaknet_active"
DNS_PREFETCH_PID="/data/local/tmp/satellite_earth_dns_prefetch.pid"

# 模块 ID（与 module.prop 一致）
SE_MOD_ID="Satellite_Earth"

# ======================================================================
# v6.3.0 核心修复：健壮的模块根目录解析
# ======================================================================
# 官方源码确认（ExecutePluginAction.kt:100-102）:
#   cmd = 'export PATH=...; cd "<pluginPath>"; sh ./action.sh; RES=$?; cd /; exit $RES'
# 因此:
#   - action.sh 的 $0 = "./action.sh"，${0%/*} = "."
#   - service.sh/post-fs-data.sh 用绝对路径调用，$0 = 绝对路径
#   - $MODPATH 仅在 customize.sh 阶段有效（未 export），action.sh 阶段不存在
#   - $AXERONDIR 在所有阶段可用（AxeronService.getDefaultEnvironment 注入）
#
# 策略优先级（按可靠性排序）:
#   1. pwd（脚本启动时 CWD = 模块根目录，最可靠）
#   2. $AXERONDIR/plugins/$SE_MOD_ID（官方环境变量推导）
#   3. $MODPATH（仅 customize.sh 阶段）
#   4. $0 推导（仅 service.sh/post-fs-data.sh 可靠）
#   5. 已知安装路径硬探测
se_resolve_moddir() {
    local candidate=""

    # 策略 1: pwd（最可靠，CWD 在 action.sh 阶段保证是模块根目录）
    candidate="$(pwd 2>/dev/null)"
    if [ -n "$candidate" ] && [ -f "$candidate/module.prop" ] 2>/dev/null; then
        echo "$candidate"
        return 0
    fi

    # 策略 2: $AXERONDIR/plugins/$SE_MOD_ID（官方环境变量，所有阶段可用）
    if [ -n "${AXERONDIR:-}" ]; then
        candidate="$AXERONDIR/plugins/$SE_MOD_ID"
        if [ -f "$candidate/module.prop" ] 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    fi

    # 策略 3: $MODPATH（仅 customize.sh 阶段有效）
    if [ -n "${MODPATH:-}" ] && [ -f "$MODPATH/module.prop" ] 2>/dev/null; then
        echo "$MODPATH"
        return 0
    fi

    # 策略 4: $0 推导（service.sh/post-fs-data.sh 用绝对路径调用时可靠）
    local raw_zero="${0:-}"
    if [ -n "$raw_zero" ] && [ "$raw_zero" != "${raw_zero#/}" ]; then
        # $0 以 / 开头（绝对路径）
        candidate="${raw_zero%/*}"
        [ -f "$candidate/module.prop" ] 2>/dev/null && { echo "$candidate"; return 0; }
        [ -f "$candidate/../module.prop" ] 2>/dev/null && {
            ( cd "$candidate/.." 2>/dev/null && pwd ) && return 0
        }
    fi

    # 策略 5: readlink -f 推导
    if command -v readlink >/dev/null 2>&1; then
        local resolved
        resolved=$(readlink -f "$raw_zero" 2>/dev/null)
        if [ -n "$resolved" ]; then
            candidate="${resolved%/*}"
            [ -f "$candidate/module.prop" ] 2>/dev/null && { echo "$candidate"; return 0; }
            [ -f "$candidate/../module.prop" ] 2>/dev/null && {
                ( cd "$candidate/.." 2>/dev/null && pwd ) && return 0
            }
        fi
    fi

    # 策略 6: 已知安装路径硬探测（按官方源码 PathHelper.java）
    local known_paths="
/data/user_de/0/com.android.shell/axeron/plugins/$SE_MOD_ID
/data/user_de/0/android/axeron/plugins/$SE_MOD_ID
/data/adb/modules/$SE_MOD_ID
/data/data/com.android.shell/axeron/plugins/$SE_MOD_ID
    "
    for p in $known_paths; do
        if [ -f "$p/module.prop" ] 2>/dev/null; then
            echo "$p"
            return 0
        fi
    done

    return 1
}

# ======================================================================
# 加载用户配置 + OEM 兼容性数据库
# ======================================================================
if [ -z "${SE_CONFIG_LOADED:-}" ]; then
    # 解析 MODDIR_ROOT（模块根目录）
    if [ -z "${MODDIR_ROOT:-}" ]; then
        MODDIR_ROOT="$(se_resolve_moddir 2>/dev/null)" || MODDIR_ROOT=""
    fi

    # MODDIR 兼容变量（业务脚本使用）
    if [ -z "${MODDIR:-}" ]; then
        MODDIR="$MODDIR_ROOT"
    fi

    # 加载 config.sh
    if [ -n "$MODDIR_ROOT" ] && [ -f "$MODDIR_ROOT/config.sh" ]; then
        . "$MODDIR_ROOT/config.sh" 2>/dev/null
        SE_CONFIG_LOADED=1
    fi

    # 加载 OEM 兼容性数据库
    if [ -n "$MODDIR_ROOT" ] && [ -f "$MODDIR_ROOT/scripts/oem_compat.sh" ]; then
        . "$MODDIR_ROOT/scripts/oem_compat.sh" 2>/dev/null
        if command -v se_probe_oem_env >/dev/null 2>&1; then
            se_probe_oem_env 2>/dev/null
        fi
    fi
fi

# ----------------------------------------------------------------------
# 默认值（config.sh 未设置时使用）
# ----------------------------------------------------------------------
: "${CARRIER:=auto}"
: "${ENABLE_WIFI_OPTIMIZE:=true}"
: "${WIFI_BAD_RSSI:=88}"
: "${WIFI_IDLE_MS:=7200000}"
: "${ENABLE_MOBILE_OPTIMIZE:=true}"
: "${ENABLE_5G_SA:=true}"
: "${ENABLE_DNS_PREFETCH:=true}"
: "${ENABLE_PRIVATE_DNS:=false}"
: "${PRIVATE_DNS_HOST:=dns.alidns.com}"
: "${ENABLE_LATE_VERIFY:=true}"
: "${ENABLE_MONITOR:=true}"
: "${ENABLE_SWITCH_NOTIFY:=true}"
: "${ENABLE_DYNAMIC_PARAMS:=true}"
: "${ENABLE_PING_FEEDBACK:=true}"
: "${ENABLE_OEM_COMPAT:=true}"
: "${WIFI_STRONG_RSSI:=60}"
: "${WIFI_WEAK_RSSI:=75}"
: "${MOBILE_STRONG_DBM:=85}"
: "${MOBILE_WEAK_DBM:=105}"
: "${PING_GOOD_MS:=80}"
: "${PING_BAD_MS:=200}"
: "${MONITOR_MIN_INTERVAL:=300}"
: "${MONITOR_NORMAL_INTERVAL:=600}"
: "${MONITOR_MAX_INTERVAL:=900}"
: "${NETWORK_READY_TIMEOUT:=10}"

# ----------------------------------------------------------------------
# 日志（带轮转）
# ----------------------------------------------------------------------
log_msg() {
    local msg="$1"
    local tag="${2:-[core]}"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "?")
    if [ -f "$SE_LOG_FILE" ]; then
        local size
        size=$(wc -c < "$SE_LOG_FILE" 2>/dev/null)
        if [ -n "$size" ] && [ "$size" -gt 262144 ] 2>/dev/null; then
            tail -100 "$SE_LOG_FILE" > "${SE_LOG_FILE}.tmp" 2>/dev/null
            mv "${SE_LOG_FILE}.tmp" "$SE_LOG_FILE" 2>/dev/null
            echo "$ts [log] 日志已轮转" >> "$SE_LOG_FILE" 2>/dev/null
        fi
    fi
    echo "$ts $tag $msg" >> "$SE_LOG_FILE" 2>/dev/null
    return 0
}

# ----------------------------------------------------------------------
# settings 安全写入/读取/删除（v6.3.0: 强化错误吞没）
# ----------------------------------------------------------------------
# v6.3.0 修复:
#   - se_put 用 if/else 替代 || true（某些 dash/busybox sh 下 || true 不可靠）
#   - 增加调试日志（写失败时记录）
#   - OEM 兼容性过滤
se_put() {
    local namespace="$1"
    local key="$2"
    local value="$3"

    if [ "${ENABLE_OEM_COMPAT:-true}" = "true" ] && [ "$(type -t se_put_safe 2>/dev/null)" = "function" ]; then
        se_put_safe "$namespace" "$key" "$value" 2>/dev/null
        return 0
    fi

    if settings put "$namespace" "$key" "$value" 2>/dev/null; then
        :
    else
        log_msg "[warn] settings put 失败: $namespace.$key=$value" "[warn]"
    fi
    return 0
}

se_get() {
    settings get "$1" "$2" 2>/dev/null
}

se_del() {
    settings delete "$1" "$2" 2>/dev/null
    return 0
}

# ----------------------------------------------------------------------
# 网络就绪检测
# ----------------------------------------------------------------------
wait_network_ready() {
    local max_wait="${1:-$NETWORK_READY_TIMEOUT}"
    case "$max_wait" in
        ''|*[!0-9]*) max_wait=10 ;;
    esac
    [ "$max_wait" -lt 1 ] 2>/dev/null && max_wait=1
    [ "$max_wait" -gt 60 ] 2>/dev/null && max_wait=60

    local start end
    start=$(date +%s 2>/dev/null || echo 0)
    while :; do
        end=$(date +%s 2>/dev/null || echo 0)
        [ $((end - start)) -ge "$max_wait" ] 2>/dev/null && return 1

        local active_net
        active_net=$(dumpsys connectivity 2>/dev/null | grep 'NetworkAgentInfo' | grep -E 'state=CONNECTED|VALIDATED' | head -1)
        if [ -n "$active_net" ]; then
            return 0
        fi
        if ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1 || \
           ping -c 1 -W 1 119.29.29.29 >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# ----------------------------------------------------------------------
# 运行环境检测
# ----------------------------------------------------------------------
detect_env() {
    if [ "${AXERON:-}" = "true" ]; then
        echo "axeron"
    elif [ -d "/data/adb/ksu" ] 2>/dev/null; then
        echo "ksu"
    elif [ -d "/data/adb/magisk" ] 2>/dev/null; then
        echo "magisk"
    elif [ -d "/data/adb/ap" ] 2>/dev/null; then
        echo "apatch"
    else
        echo "unknown"
    fi
}

is_axeron_env() {
    [ "${AXERON:-}" = "true" ]
}

# ----------------------------------------------------------------------
# 网络类型检测（v6.3.0: 增强 dumpsys 解析兼容性）
# ----------------------------------------------------------------------
se_detect_network_type() {
    local dump
    dump=$(dumpsys connectivity 2>/dev/null)

    local wifi_conn=""
    local mobile_conn=""

    # 多种匹配模式兼容不同 ROM
    # 标准 AOSP: NetworkAgentInfo{ WIFI {... state=CONNECTED ...}}
    # MIUI: 可能为 WIFI {... VALIDATED ...}
    # ColorOS: NetworkAgentInfo{ WIFI {... state=CONNECTED ...}}
    if echo "$dump" | grep -qE 'NetworkAgentInfo.*WIFI.*(state=CONNECTED|VALIDATED|CONNECTED.*VALIDATED)'; then
        wifi_conn=1
    elif echo "$dump" | grep -qE 'WIFI.*state=CONNECTED'; then
        wifi_conn=1
    fi

    if echo "$dump" | grep -qE 'NetworkAgentInfo.*MOBILE.*(state=CONNECTED|VALIDATED|CONNECTED.*VALIDATED)'; then
        mobile_conn=1
    elif echo "$dump" | grep -qE 'MOBILE.*state=CONNECTED'; then
        mobile_conn=1
    fi

    if [ -n "$wifi_conn" ] && [ -n "$mobile_conn" ]; then
        echo "dual"
    elif [ -n "$wifi_conn" ]; then
        echo "wifi"
    elif [ -n "$mobile_conn" ]; then
        echo "mobile"
    else
        echo "none"
    fi
}

# ----------------------------------------------------------------------
# 运营商自动识别
# ----------------------------------------------------------------------
se_detect_carrier() {
    local mccmnc
    mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
    [ -z "$mccmnc" ] && mccmnc=$(getprop gsm.operator.numeric 2>/dev/null | head -1)
    case "$mccmnc" in
        46011|46012)                              echo "telecom" ;;
        46001|46006|46009)                        echo "unicom" ;;
        46000|46002|46004|46007|46008|46013|46015|46017) echo "mobile" ;;
        46020)                                    echo "ctn" ;;
        *)                                        echo "auto" ;;
    esac
}

# ----------------------------------------------------------------------
# v6.3.0: WiFi RSSI 读取（多 ROM 兼容增强）
# ----------------------------------------------------------------------
# 原 v6.2.0 仅匹配 'mRssi:'，在部分 ROM 上字段名/缩进不同
# v6.3.0 新增多种匹配模式：
#   - 标准 AOSP: dumpsys wifi 输出含 'mRssi: -65'
#   - MIUI/HyperOS: 可能为 'mRssi=-65' 或 'RSSI: -65'
#   - ColorOS: 'mRssi: -65'
#   - 部分 ROM: dumpsys wifi | grep 'WifiInfo' 行内含 RSSI
se_get_wifi_rssi() {
    local dump result
    dump=$(dumpsys wifi 2>/dev/null)

    # 模式 1: mRssi: -65 (标准 AOSP)
    result=$(echo "$dump" | awk -F': ' '/^[[:space:]]*mRssi:/ {gsub(/[^0-9-].*/, "", $2); print $2; exit}' 2>/dev/null)
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 模式 2: mRssi=-65 (部分 ROM 用等号)
    result=$(echo "$dump" | grep -oE 'mRssi=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 模式 3: RSSI: -65 (部分 ROM 简写)
    result=$(echo "$dump" | grep -oE 'RSSI: [-]?[0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 模式 4: WifiInfo 行内 mRssi=-65
    result=$(echo "$dump" | grep 'WifiInfo' 2>/dev/null | grep -oE 'mRssi=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 模式 5: cmd wifi status (Android 11+)
    result=$(cmd wifi status 2>/dev/null | grep -i 'RSSI' | grep -oE '[-]?[0-9]+' | head -1)
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 全部失败
    echo ""
}

# ----------------------------------------------------------------------
# v6.3.0: 移动信号 dBm 读取（多 ROM 兼容增强）
# ----------------------------------------------------------------------
se_get_mobile_dbm() {
    local reg dbm
    reg=$(dumpsys telephony.registry 2>/dev/null)

    # 模式 1: mDbm=-95 (标准 AOSP，等号)
    dbm=$(echo "$reg" | grep -oE 'mDbm=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$dbm" ] && { echo "$dbm"; return 0; }

    # 模式 2: mDbm: -95 (部分 ROM 用冒号)
    dbm=$(echo "$reg" | grep -oE 'mDbm: [-]?[0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
    [ -n "$dbm" ] && { echo "$dbm"; return 0; }

    # 模式 3: mSignalStrength 行内第一个负数
    dbm=$(echo "$reg" | grep 'mSignalStrength' 2>/dev/null | head -1 | grep -oE '[-][0-9]+' | head -1)
    [ -n "$dbm" ] && { echo "$dbm"; return 0; }

    # 模式 4: grep -A 30 mSignalStrength 后找 mDbm
    dbm=$(echo "$reg" | grep -A 30 'mSignalStrength' 2>/dev/null | grep -E 'mDbm' | head -1 | grep -oE '[-]?[0-9]+' | head -1)
    [ -n "$dbm" ] && { echo "$dbm"; return 0; }

    # 全部失败
    echo ""
}

se_get_mobile_level() {
    local reg level
    reg=$(dumpsys telephony.registry 2>/dev/null)

    # 模式 1: mLevel=3
    level=$(echo "$reg" | grep -oE 'mLevel=[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$level" ] && { echo "$level"; return 0; }

    # 模式 2: mLevel: 3
    level=$(echo "$reg" | grep -oE 'mLevel: [0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
    [ -n "$level" ] && { echo "$level"; return 0; }

    # 模式 3: grep -A 20 mSignalStrength
    level=$(echo "$reg" | grep -A 20 'mSignalStrength' 2>/dev/null | grep -E 'mLevel' | head -1 | grep -oE '[0-9]+' | head -1)
    [ -n "$level" ] && { echo "$level"; return 0; }

    echo ""
}

# ----------------------------------------------------------------------
# v6.3.3: 公网延迟检测（增强后台 nohup 环境容错）
# ----------------------------------------------------------------------
# v6.3.2 问题：调度器后台 nohup 子进程下 ping 命令可能因管道/权限问题
#             返回空，导致通知"延迟: ? ms"
# v6.3.3 修复：1. ping 失败时用 dumpsys pingstate/connectivity 兜底
#             2. 最后才返回 ?
se_get_ping_ms() {
    local result

    # 方法 1: ping 阿里 DNS（前台/后台都尝试）
    result=$(ping -c 1 -W 2 223.5.5.5 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    # 方法 2: ping 腾讯 DNS
    result=$(ping -c 1 -W 2 119.29.29.29 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    # 方法 3: ping 114 DNS
    result=$(ping -c 1 -W 2 114.114.114.114 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    # v6.3.3: 方法 4 - ping 本地网关（后台环境兜底，几乎不会失败）
    local gateway
    gateway=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        result=$(ping -c 1 -W 2 "$gateway" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
    fi

    echo "?"
    return 0
}

# ----------------------------------------------------------------------
# 通知发送
# ----------------------------------------------------------------------
se_notify() {
    local title="$1"
    local body="$2"
    [ -z "$title" ] && return 0
    [ -z "$body" ] && body=" "
    cmd notification post -S bigtext -t "$title" "$SE_NOTIFY_TAG" "$body" >/dev/null 2>&1
    return 0
}

se_notify_cancel() {
    cmd notification cancel "$SE_NOTIFY_TAG" >/dev/null 2>&1
    return 0
}

# ----------------------------------------------------------------------
# 进程管理
# ----------------------------------------------------------------------
se_monitor_running() {
    [ -f "$SE_PID_FILE" ] || return 1
    local pid
    pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null
}

se_monitor_pid() {
    [ -f "$SE_PID_FILE" ] || return 1
    cat "$SE_PID_FILE" 2>/dev/null
}

# ======================================================================
# 动态参数计算引擎
# ======================================================================
se_clamp() {
    local v="$1" min="$2" max="$3"
    case "$v$min$max" in
        ''|*[!0-9-]*) echo "$min"; return ;;
    esac
    [ "$v" -lt "$min" ] 2>/dev/null && { echo "$min"; return; }
    [ "$v" -gt "$max" ] 2>/dev/null && { echo "$max"; return; }
    echo "$v"
}

se_lerp() {
    local x="$1" x1="$2" y1="$3" x2="$4" y2="$5"
    local p
    for p in "$x" "$x1" "$y1" "$x2" "$y2"; do
        case "$p" in
            ''|*[!0-9-]*) echo "$y1"; return ;;
        esac
    done
    [ "$x" -le "$x1" ] 2>/dev/null && { echo "$y1"; return; }
    [ "$x" -ge "$x2" ] 2>/dev/null && { echo "$y2"; return; }
    awk -v x="$x" -v x1="$x1" -v y1="$y1" -v x2="$x2" -v y2="$y2" \
        'BEGIN { printf "%d", y1 + (y2-y1)*(x-x1)/(x2-x1) }' 2>/dev/null || echo "$y1"
}

se_wifi_level() {
    local rssi
    rssi=$(se_get_wifi_rssi)
    # v6.3.1: 空值容错
    if [ -z "$rssi" ] || [ "$rssi" = "?" ]; then
        echo "unknown"
        return 0
    fi

    # v6.3.1: 严格数值校验
    local abs_rssi=""
    case "$rssi" in
        ''|*[!0-9-]*) echo "unknown"; return 0 ;;
    esac
    if [ "$rssi" -lt 0 ] 2>/dev/null; then
        abs_rssi=$((-rssi))
    elif [ "$rssi" -gt 0 ] 2>/dev/null; then
        abs_rssi="$rssi"
    else
        echo "unknown"
        return 0
    fi

    if [ "$abs_rssi" -lt "$WIFI_STRONG_RSSI" ] 2>/dev/null; then
        echo "strong"
    elif [ "$abs_rssi" -lt "$WIFI_WEAK_RSSI" ] 2>/dev/null; then
        echo "normal"
    else
        echo "weak"
    fi
    return 0
}

se_mobile_level() {
    local mlevel
    mlevel=$(se_get_mobile_level)
    if [ -n "$mlevel" ]; then
        case "$mlevel" in
            4)         echo "strong"; return 0 ;;
            2|3)       echo "normal"; return 0 ;;
            0|1)       echo "weak"; return 0 ;;
            *)         echo "normal"; return 0 ;;
        esac
    fi

    local dbm abs_dbm
    dbm=$(se_get_mobile_dbm)
    # v6.3.1: 空值容错（无 SIM 卡场景）
    if [ -z "$dbm" ] || [ "$dbm" = "?" ]; then
        echo "unknown"
        return 0
    fi
    case "$dbm" in
        ''|*[!0-9-]*) echo "unknown"; return 0 ;;
    esac
    if [ "$dbm" -lt 0 ] 2>/dev/null; then
        abs_dbm=$((-dbm))
    elif [ "$dbm" -gt 0 ] 2>/dev/null; then
        abs_dbm="$dbm"
    else
        echo "unknown"
        return 0
    fi

    if [ "$abs_dbm" -lt "$MOBILE_STRONG_DBM" ] 2>/dev/null; then
        echo "strong"
    elif [ "$abs_dbm" -le "$MOBILE_WEAK_DBM" ] 2>/dev/null; then
        echo "normal"
    else
        echo "weak"
    fi
    return 0
}

se_overall_level() {
    local net_type="$1" wifi_lvl="$2" mobile_lvl="$3" ping_ms="$4"

    local ping_critical=0 ping_bad=0
    if [ "$ENABLE_PING_FEEDBACK" = "true" ] && [ "$ping_ms" != "?" ]; then
        case "$ping_ms" in
            ''|*[!0-9]*) ;;
            *)
                [ "$ping_ms" -ge "$PING_BAD_MS" ] 2>/dev/null && ping_critical=1
                [ "$ping_ms" -ge "$PING_GOOD_MS" ] 2>/dev/null && [ "$ping_ms" -lt "$PING_BAD_MS" ] 2>/dev/null && ping_bad=1
                ;;
        esac
    fi

    local base_level
    case "$net_type" in
        wifi)   base_level="$wifi_lvl" ;;
        mobile) base_level="$mobile_lvl" ;;
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

    if [ "$ping_critical" = "1" ]; then
        if [ "$base_level" = "weak" ]; then
            echo "critical"
        else
            echo "weak"
        fi
        return
    fi
    if [ "$ping_bad" = "1" ] && [ "$base_level" = "strong" ]; then
        echo "normal"
        return
    fi
    echo "$base_level"
}

se_compute_dynamic_params() {
    local level="$1"
    local rssi_abs="$2"

    local interval scan_ms bad_rssi mobile_ka ping_chk

    # v6.3.3: 默认值兜底,确保变量永远非空
    interval="${MONITOR_NORMAL_INTERVAL:-600}"
    scan_ms=15000
    bad_rssi=-88
    mobile_ka=1
    ping_chk=1

    case "$level" in
        strong)
            interval="${MONITOR_MAX_INTERVAL:-900}"; scan_ms=30000; bad_rssi=-70;  mobile_ka=1; ping_chk=0 ;;
        normal)
            interval="${MONITOR_NORMAL_INTERVAL:-600}"; scan_ms=15000; bad_rssi=-88;  mobile_ka=1; ping_chk=1 ;;
        weak)
            interval="${MONITOR_MIN_INTERVAL:-300}"; scan_ms=10000; bad_rssi=-95;  mobile_ka=1; ping_chk=1 ;;
        critical)
            interval="${MONITOR_MIN_INTERVAL:-300}"; scan_ms=8000;  bad_rssi=-100; mobile_ka=1; ping_chk=1 ;;
        *)
            interval="${MONITOR_NORMAL_INTERVAL:-600}"; scan_ms=15000; bad_rssi=-88;  mobile_ka=1; ping_chk=1 ;;
    esac

    # v6.3.3: 动态插值前严格校验 rssi_abs 是正整数
    if [ "$ENABLE_DYNAMIC_PARAMS" = "true" ] && [ "$level" != "critical" ]; then
        case "$rssi_abs" in
            ''|*[!0-9]*)
                # rssi_abs 非正整数,跳过插值,用默认值
                ;;
            *)
                if [ "$rssi_abs" -gt 0 ] 2>/dev/null; then
                    local rssi_clamped
                    rssi_clamped=$(se_clamp "$rssi_abs" 40 100)
                    # v6.3.3: 确保 se_lerp 返回非空
                    local _new_scan _new_bad
                    _new_scan=$(se_lerp "$rssi_clamped" 40 30000 100 8000)
                    _new_bad=$(se_lerp "$rssi_clamped" 40 -65 100 -100)
                    [ -n "$_new_scan" ] && scan_ms="$_new_scan"
                    [ -n "$_new_bad" ] && bad_rssi="$_new_bad"
                fi
                ;;
        esac
    fi

    # v6.3.3: 最终输出前再次确保所有字段非空
    [ -z "$interval" ] && interval=600
    [ -z "$scan_ms" ] && scan_ms=15000
    [ -z "$bad_rssi" ] && bad_rssi=-88
    [ -z "$mobile_ka" ] && mobile_ka=1
    [ -z "$ping_chk" ] && ping_chk=1

    echo "${interval} ${scan_ms} ${bad_rssi} ${mobile_ka} ${ping_chk}"
    return 0
}

# ----------------------------------------------------------------------
# 模块自检（v6.3.0: 用 pwd + AXERONDIR 双重确认）
# ----------------------------------------------------------------------
se_self_check() {
    echo "=== 卫星地球 Pro v${SE_VERSION} 自检 ==="
    echo ""
    echo "[环境]"
    echo "  引擎       : $(detect_env)"
    echo "  AXERON     : ${AXERON:-未设置}"
    echo "  AXERONVER  : ${AXERONVER:-未知}"
    echo "  AXERONDIR  : ${AXERONDIR:-未设置}"
    echo "  API        : ${API:-未设置} (实测 $(getprop ro.build.version.sdk 2>/dev/null | head -1))"
    echo "  ARCH       : ${ARCH:-未知} (实测 $(getprop ro.product.cpu.abi 2>/dev/null | head -1))"
    echo "  MODPATH    : ${MODPATH:-未设置}"
    echo "  MODDIR_ROOT: ${MODDIR_ROOT:-未解析}"
    echo "  pwd        : $(pwd 2>/dev/null)"
    echo "  \$0         : ${0:-空}"
    echo ""

    # v6.3.0: 重新解析一次，确认 MODDIR_ROOT 有效
    if [ -z "${MODDIR_ROOT:-}" ] || [ ! -d "${MODDIR_ROOT:-}" ]; then
        echo "[!] MODDIR_ROOT 无效，尝试重新解析..."
        MODDIR_ROOT="$(se_resolve_moddir 2>/dev/null)" || MODDIR_ROOT=""
        MODDIR="$MODDIR_ROOT"
    fi

    local check_dir="${MODDIR_ROOT:-${MODPATH:-${MODDIR:-}}}"
    echo "[关键文件] (检查目录: $check_dir)"
    if [ -n "$check_dir" ] && [ -d "$check_dir" ]; then
        for f in module.prop customize.sh post-fs-data.sh service.sh action.sh uninstall.sh config.sh system.prop LICENSE; do
            if [ -f "$check_dir/$f" ]; then
                echo "  [OK] $f"
            else
                echo "  [缺失] $f"
            fi
        done
        for f in scripts/common.sh scripts/oem_compat.sh scripts/wifi.sh scripts/carrier.sh scripts/dns.sh scripts/weaknet.sh scripts/monitor.sh scripts/network_info.sh webroot/index.html; do
            if [ -f "$check_dir/$f" ]; then
                echo "  [OK] $f"
            else
                echo "  [缺失] $f"
            fi
        done
    else
        echo "  [!] 检查目录不存在或不可访问"
        echo "  尝试手动诊断:"
        echo "    pwd = $(pwd 2>/dev/null)"
        echo "    AXERONDIR = ${AXERONDIR:-未设置}"
        echo "    ls /data/user_de/0/com.android.shell/axeron/plugins/ 2>/dev/null:"
        ls /data/user_de/0/com.android.shell/axeron/plugins/ 2>/dev/null | head -5 | sed 's/^/      /'
    fi
    echo ""

    # OEM 兼容性信息
    if [ "$(type -t se_show_oem_info 2>/dev/null)" = "function" ]; then
        se_show_oem_info
    fi

    echo "[关键 settings 写入验证]"
    echo "  wifi_scan_throttle_enabled      = $(se_get global wifi_scan_throttle_enabled) (期望 0)"
    echo "  wifi_suspend_optimizations_enabled = $(se_get global wifi_suspend_optimizations_enabled) (期望 0)"
    echo "  mobile_data_always_on           = $(se_get global mobile_data_always_on) (期望 1)"
    echo "  private_dns_mode                = $(se_get global private_dns_mode)"
    echo ""
    echo "[动态参数引擎]"
    echo "  ENABLE_DYNAMIC_PARAMS = ${ENABLE_DYNAMIC_PARAMS}"
    echo "  ENABLE_PING_FEEDBACK  = ${ENABLE_PING_FEEDBACK}"
    echo "  ENABLE_OEM_COMPAT     = ${ENABLE_OEM_COMPAT}"
    echo ""
    echo "[实时信号]"
    local rssi dbm ping_ms
    rssi=$(se_get_wifi_rssi)
    dbm=$(se_get_mobile_dbm)
    ping_ms=$(se_get_ping_ms)
    echo "  WiFi RSSI      : ${rssi:-未连接}"
    echo "  移动 dBm       : ${dbm:-未检测}"
    echo "  公网延迟       : ${ping_ms} ms"
    echo ""
    echo "[调度器]"
    if se_monitor_running; then
        echo "  状态       : 运行中 (PID=$(se_monitor_pid))"
    else
        echo "  状态       : 未运行"
    fi
    echo ""
    echo "[日志]"
    if [ -f "$SE_LOG_FILE" ]; then
        local size lines
        size=$(wc -c < "$SE_LOG_FILE" 2>/dev/null)
        lines=$(wc -l < "$SE_LOG_FILE" 2>/dev/null)
        echo "  路径       : $SE_LOG_FILE"
        echo "  大小       : ${size} 字节 (${lines} 行)"
    else
        echo "  日志文件不存在"
    fi
}
