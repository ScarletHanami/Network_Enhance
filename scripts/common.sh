#!/system/bin/sh
# common.sh — 网络增强 公共函数库
#
# 严格遵循 AxManager 官方插件协议 + 免Root约束
# 官方文档: https://fahrez182.github.io/AxManager/plugin/what-is-plugin.html

# ----------------------------------------------------------------------
# 路径与版本常量
# ----------------------------------------------------------------------
SE_VERSION="1.1.4"
SE_VERSION_CODE="114"
SE_LOG_TAG="NetworkEnhance"

# 日志路径优先 /data/local/tmp（ADB 必写、稳定）
SE_LOG_FILE="/data/local/tmp/network_enhance.log"
if [ ! -w "$(dirname "$SE_LOG_FILE")" ] 2>/dev/null; then
    SE_LOG_FILE="/storage/emulated/0/network_enhance.log"
fi

# 运行时文件（network_enhance 前缀统一）
SE_PID_FILE="/data/local/tmp/network_enhance_monitor.pid"
SE_STATE_FILE="/data/local/tmp/network_enhance_monitor.state"
SE_NOTIFY_TAG="network_enhance_monitor"

# weaknet 互锁标志 + DNS 预热 PID 锁
WEAKNET_ACTIVE_FLAG="/data/local/tmp/network_enhance_weaknet_active"
DNS_PREFETCH_PID="/data/local/tmp/network_enhance_dns_prefetch.pid"

# 5G 假满格降级备份文件
SE_5G_BACKUP_FILE="/data/local/tmp/network_enhance_5g_backup"

# 模块 ID（与 module.prop 一致）
SE_MOD_ID="Network_Enhance"

# ======================================================================
# 健壮的模块根目录解析
# ======================================================================
# 参考 AxManager ExecutePluginAction.kt:
#   cmd = 'export PATH=...; cd "<pluginPath>"; sh ./action.sh; RES=$?; cd /; exit $RES'
# 因此:
#   - action.sh 的 $0 = "./action.sh"，${0%/*} = "."
#   - service.sh/post-fs-data.sh 用绝对路径调用，$0 = 绝对路径
#   - $MODPATH 仅在 customize.sh 阶段有效（未 export）
#   - $AXERONDIR 在所有阶段可用（AxeronService.getDefaultEnvironment 注入）
#
# 策略优先级（按可靠性排序）:
#   0. $MODDIR 环境变量
#   1. pwd（脚本启动时 CWD = 模块根目录，最可靠）
#   2. $AXERONDIR/plugins/$SE_MOD_ID（官方环境变量推导）
#   3. $MODPATH（仅 customize.sh 阶段）
#   4. $0 推导（仅 service.sh/post-fs-data.sh 可靠）
#   5. readlink -f 推导
#   6. 已知安装路径硬探测
se_resolve_moddir() {
    local candidate=""

    # 策略 0: 环境变量 MODDIR
    if [ -n "${MODDIR:-}" ] && [ -f "$MODDIR/module.prop" ] 2>/dev/null; then
        echo "$MODDIR"
        return 0
    fi

    # 策略 1: pwd（CWD 在 action.sh 阶段保证是模块根目录）
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

    # 策略 6: 已知安装路径硬探测
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

# 信号阈值
: "${WIFI_STRONG_RSSI:=60}"
: "${WIFI_WEAK_RSSI:=75}"
: "${MOBILE_STRONG_DBM:=85}"
: "${MOBILE_WEAK_DBM:=105}"
: "${PING_GOOD_MS:=80}"
: "${PING_BAD_MS:=200}"

# 检测间隔（统一为 120 秒）
: "${MONITOR_MIN_INTERVAL:=120}"
: "${MONITOR_NORMAL_INTERVAL:=120}"
: "${MONITOR_MAX_INTERVAL:=120}"
: "${NETWORK_READY_TIMEOUT:=10}"

# 5G 假满格判定参数
: "${ENABLE_FAKE_5G_DETECTION:=true}"
: "${FAKE_5G_RSRP_THRESHOLD:=-85}"
: "${FAKE_5G_SINR_THRESHOLD:=0}"
: "${FAKE_5G_PING_THRESHOLD:=200}"
: "${FAKE_5G_RECOVERY_COUNT:=3}"

# 5G 降级后无网络回退参数
: "${DEGRADE_NO_NET_ROLLBACK_COUNT:=2}"

# 4G+ 跳频防护参数
: "${ENABLE_LTE_LOCK_FOR_GAME:=true}"

# 最低 Android 版本要求
: "${MIN_API_LEVEL:=34}"

# ----------------------------------------------------------------------
# Android 版本检测
# ----------------------------------------------------------------------
# AxManager 要求 Android 11+, 本模块要求 Android 14+
se_get_api() {
    getprop ro.build.version.sdk 2>/dev/null | head -1
}

# 返回 0 = Android 14+, 1 = 低于 Android 14
se_is_android_14_plus() {
    local api
    api=$(se_get_api)
    case "$api" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$api" -ge 34 ] ;;
    esac
}

# ======================================================================
# dumpsys 缓存 — 同轮次内共享，避免重复调用
# ======================================================================
# 原理：dumpsys telephony.registry 读取 TelephonyRegistry 内存快照，
#       TelephonyRegistry 被 RIL 以 200ms-1s 频率推送更新（事件驱动），
#       因此 dumpsys 本身即为实时快照，无需跨轮次缓存。
# 用法：se_dumpsys_cached <key>  (key: telephony.registry / wifi / connectivity)
#       se_dumpsys_clear      清空缓存（monitor 每轮开始时调用）
# 生命周期：se_dumpsys_clear → 首次调用 dumpsys → 写入缓存 → 同轮次复用
#           → 下一轮 se_dumpsys_clear → 重新获取最新数据
# ======================================================================
SE_DUMPSYS_CACHE_DIR="/data/local/tmp/network_enhance_dumpsys_cache"

se_dumpsys_cached() {
    local key="$1"
    [ -z "$key" ] && return 1
    local cache_file="$SE_DUMPSYS_CACHE_DIR/${key}.txt"

    # 有缓存直接用（生命周期由 se_dumpsys_clear 控制，不设 TTL）
    if [ -f "$cache_file" ]; then
        cat "$cache_file" 2>/dev/null
        return 0
    fi

    # 首次调用：执行 dumpsys 并写入缓存
    mkdir -p "$SE_DUMPSYS_CACHE_DIR" 2>/dev/null
    local output
    case "$key" in
        telephony.registry) output=$(dumpsys telephony.registry 2>/dev/null) ;;
        wifi)               output=$(dumpsys wifi 2>/dev/null) ;;
        connectivity)       output=$(dumpsys connectivity 2>/dev/null) ;;
        *)                  output=$(dumpsys "$key" 2>/dev/null) ;;
    esac
    echo "$output" > "$cache_file" 2>/dev/null
    echo "$output"
    return 0
}

se_dumpsys_clear() {
    rm -rf "$SE_DUMPSYS_CACHE_DIR" 2>/dev/null
    return 0
}

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
# settings 安全写入/读取/删除
# ----------------------------------------------------------------------
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
# settings 写入并验证（华为/荣耀等受限品牌可靠性验证）
# ----------------------------------------------------------------------
# 写入后循环读回验证, 最多 3 秒, 失败则记录日志并返回 1
# settings 写入后系统服务同步可能有延迟, 循环验证更健壮
se_put_verify() {
    local namespace="$1"
    local key="$2"
    local value="$3"

    se_put "$namespace" "$key" "$value"

    local verify=""
    local i
    for i in 1 2 3; do
        sleep 1 2>/dev/null
        verify=$(se_get "$namespace" "$key" 2>/dev/null)
        if [ "$verify" = "$value" ]; then
            return 0
        fi
    done

    log_msg "[verify] 写入验证失败: $namespace.$key=$value (实际=${verify:-空}, brand=${SE_BRAND:-?})" "[warn]"
    return 1
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
# 网络类型检测（返回 5G/4G/3G/2G/wifi/none, 避免 dual 中间态）
# ----------------------------------------------------------------------
# dumpsys connectivity 解析失败时 fallback 到 getprop gsm.network.type
# 双连接时优先返回移动网络制式，前端可直接显示
se_detect_network_type() {
    local dump
    dump=$(dumpsys connectivity 2>/dev/null)

    local wifi_conn=""
    local mobile_conn=""

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

    # 双连接时优先返回移动网络制式 (5G/4G), 不再返回 dual
    if [ -n "$mobile_conn" ]; then
        # 移动网络已连接, 进一步判定 5G/4G/3G/2G
        local net_type_prop
        net_type_prop=$(getprop gsm.network.type 2>/dev/null | head -1)
        case "$net_type_prop" in
            *NR*|*nr*)                  echo "5G"; return 0 ;;
            *LTE*|*lte*)                echo "4G"; return 0 ;;
            *HSDPA*|*HSUPA*|*HSPA*|*UMTS*) echo "3G"; return 0 ;;
            *EDGE*|*GPRS*)              echo "2G"; return 0 ;;
            *CDMA*|*EvDo*|*TDSCDMA*)    echo "3G"; return 0 ;;
            *)                          echo "4G"; return 0 ;;  # 默认按 4G
        esac
    fi

    if [ -n "$wifi_conn" ]; then
        echo "wifi"
        return 0
    fi

    # dumpsys 解析失败时 fallback 到 getprop gsm.network.type
    # 真实输出如 NR_SA,Unknown → 含 NR 判定为 5G
    local net_type_prop2
    net_type_prop2=$(getprop gsm.network.type 2>/dev/null | head -1)
    case "$net_type_prop2" in
        *NR*|*nr*)                  echo "5G"; return 0 ;;
        *LTE*|*lte*)                echo "4G"; return 0 ;;
        *HSDPA*|*HSUPA*|*HSPA*|*UMTS*) echo "3G"; return 0 ;;
        *EDGE*|*GPRS*)              echo "2G"; return 0 ;;
        *CDMA*|*EvDo*|*TDSCDMA*)    echo "3G"; return 0 ;;
        *)
            # 进一步检查 WiFi 状态
            local wifi_state
            wifi_state=$(cmd wifi status 2>/dev/null | grep -i 'Wi-Fi is' | head -1)
            if echo "$wifi_state" | grep -qi 'connected\|enabled'; then
                echo "wifi"
                return 0
            fi
            echo "none"
            return 0
            ;;
    esac
}

# ----------------------------------------------------------------------
# 运营商自动识别（兼容双卡逗号分隔 + MCC-MNC + alpha 名称匹配）
# ----------------------------------------------------------------------
# 双卡设备可能返回 "46000,46007"，截取第一个值匹配
# 补全 MCC-MNC 范围 + gsm.sim.operator.alpha 名称匹配（CMCC/CUCC/CTCC）
se_detect_carrier() {
    local mccmnc mccmnc_first alpha

    # 获取 MCC-MNC（可能含逗号，如 "46000,46007"）
    mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
    [ -z "$mccmnc" ] && mccmnc=$(getprop gsm.operator.numeric 2>/dev/null | head -1)

    # 处理逗号分隔的多个值，取第一个
    if [ -n "$mccmnc" ]; then
        mccmnc_first=$(echo "$mccmnc" | cut -d',' -f1 | tr -d ' ')
    else
        mccmnc_first=""
    fi

    # 按 MCC-MNC 匹配（补全所有运营商）
    case "$mccmnc_first" in
        # 电信 (telecom): 46003/46005/46011/46012 + 原 46011/46012
        46003|46005|46011|46012)    echo "telecom"; return 0 ;;
        # 联通 (unicom): 46001/46006/46009
        46001|46006|46009)          echo "unicom"; return 0 ;;
        # 移动 (mobile): 46000/46002/46004/46007/46008/46013/46015/46017
        # 注意: 46015 在部分文献归广电，但实际双卡场景可能为移动，保留移动
        46000|46002|46004|46007|46008|46013|46017) echo "mobile"; return 0 ;;
        # 广电 (ctn): 46015/46020
        46015|46020)                echo "ctn"; return 0 ;;
    esac

    # MCC-MNC 匹配失败时，通过运营商名称（alpha）匹配
    # 双卡设备可能返回 "CMCC,CMCC" 或 "China Mobile,CMCC"
    alpha=$(getprop gsm.sim.operator.alpha 2>/dev/null | head -1)
    [ -z "$alpha" ] && alpha=$(getprop gsm.operator.alpha 2>/dev/null | head -1)

    if [ -n "$alpha" ]; then
        # 转小写匹配（兼容大小写差异）
        local alpha_lower
        alpha_lower=$(echo "$alpha" | tr '[:upper:]' '[:lower:]')
        case "$alpha_lower" in
            # 移动: CMCC / China Mobile / 中国移动 / 移动
            *cmcc*|*china\ mobile*|*中国移动*|*移动*)   echo "mobile"; return 0 ;;
            # 联通: CUCC / China Unicom / 中国联通 / 联通
            *cucc*|*china\ unicom*|*中国联通*|*联通*)    echo "unicom"; return 0 ;;
            # 电信: CTCC / China Telecom / 中国电信 / 电信
            *ctcc*|*china\ telecom*|*中国电信*|*电信*)   echo "telecom"; return 0 ;;
            # 广电: CBN / China Broadcasting / 中国广电 / 广电
            *cbn*|*china\ broadcasting*|*中国广电*|*广电*) echo "ctn"; return 0 ;;
        esac
    fi

    # 全部匹配失败
    echo "auto"
}

# ----------------------------------------------------------------------
# 运营商默认 preferred_network_mode 值
# ----------------------------------------------------------------------
# 参考 AOSP RILConstants.java:
#   https://android.googlesource.com/platform/frameworks/base/+/master/telephony/java/com/android/internal/telephony/RILConstants.java
# 修正说明:
#   电信 26 (不含CDMA, 失语音) → 27
#   移动 23 (NR only, 缺4G回退) → 32
#   广电 26 → 33
se_get_carrier_default_mode() {
    local carrier="$1"
    case "$carrier" in
        telecom) echo 27 ;;  # NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA
        mobile)  echo 32 ;;  # NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA
        unicom)  echo 26 ;;  # NETWORK_MODE_NR_LTE_GSM_WCDMA
        ctn)     echo 33 ;;  # NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA
        *)       echo 26 ;;  # 默认联通兼容
    esac
}

# 4G-only 模式（锁定 LTE, 用于游戏模式）
# RILConstants: NETWORK_MODE_LTE_ONLY = 11
se_get_lte_only_mode() {
    echo 11
}

# 4G 优先模式（无5G, 用于5G假满格降级）
# RILConstants: NETWORK_MODE_LTE_GSM_WCDMA = 9
se_get_lte_preferred_mode() {
    echo 9
}

# ----------------------------------------------------------------------
# WiFi RSSI 读取（多重 fallback, 数值范围校验）
# ----------------------------------------------------------------------
# 策略:
#   1. cmd wifi status 提取: 兼容 RSSI: -60 / rssi=-60 / mRssi=-60 等格式
#      提取到数值后, 只要 -100 到 -10 之间, 认为合法 dBm
#   2. 正数(0-100)判定为等级或链路速率, 丢弃, 继续下一步
#   3. dumpsys wifi 提取: grep -iE 'mRssi|rssi', 兼容多种格式
#   4. 兜底: dumpsys wifi 抓取第一个两位数负数作为估算值
se_get_wifi_rssi() {
    local result raw_val

    # ====== 阶段 1: cmd wifi status ======
    if se_is_android_14_plus; then
        # 1a: 提取 RSSI 关键字后的数字 (兼容 RSSI: -60 / rssi=-60 / mRssi=-60 / RSSI -60)
        raw_val=$(cmd wifi status 2>/dev/null | grep -iE 'rssi' | grep -oE '[-]?[0-9]+' | head -1)
        if [ -n "$raw_val" ]; then
            # 数值范围校验: -100 到 -10 为合法 dBm
            if [ "$raw_val" -le -10 ] 2>/dev/null && [ "$raw_val" -ge -100 ] 2>/dev/null; then
                echo "$raw_val"; return 0
            fi
            # 正数 0-100 = 等级, 丢弃继续; >100 可能是绝对值
            if [ "$raw_val" -gt 100 ] 2>/dev/null; then
                echo "-$raw_val"; return 0
            fi
            # 0-100 正数, 继续走 fallback
            :
        fi
    fi

    # ====== 阶段 2: dumpsys wifi（使用缓存避免重复调用）======
    local dump
    dump=$(se_dumpsys_cached wifi 2>/dev/null)

    # 2a: mRssi: -65 (标准 AOSP, 冒号格式)
    result=$(echo "$dump" | awk -F': ' '/^[[:space:]]*mRssi:/ {gsub(/[^0-9-].*/, "", $2); print $2; exit}' 2>/dev/null)
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        echo "$result"; return 0
    fi

    # 2b: mRssi=-65 (等号格式)
    result=$(echo "$dump" | grep -oE 'mRssi=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        echo "$result"; return 0
    fi

    # 2c: RSSI: -65 或 RSSI = -65 (简写格式)
    result=$(echo "$dump" | grep -oE 'RSSI:?\s*[-]?[0-9]+' 2>/dev/null | head -1 | grep -oE '[-]?[0-9]+')
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        echo "$result"; return 0
    fi

    # 2d: WifiInfo 行内 mRssi=-65
    result=$(echo "$dump" | grep 'WifiInfo' 2>/dev/null | grep -oE 'mRssi=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        echo "$result"; return 0
    fi

    # 2e: 任意含 rssi 行的第一个负数 (宽泛匹配)
    result=$(echo "$dump" | grep -iE 'rssi' | grep -oE '\-[0-9]+' | head -1)
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        echo "$result"; return 0
    fi

    # ====== 阶段 3: cmd wifi status 任意负数（非 Android 14+ 也尝试）======
    result=$(cmd wifi status 2>/dev/null | grep -iE 'rssi' | grep -oE '\-[0-9]+' | head -1)
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        echo "$result"; return 0
    fi

    # ====== 阶段 4: 兜底 - dumpsys wifi 第一个两位数负数估算 ======
    result=$(echo "$dump" | grep -oE '\-[0-9]{2}' | head -1)
    if [ -n "$result" ] && [ "$result" -le -10 ] 2>/dev/null && [ "$result" -ge -100 ] 2>/dev/null; then
        log_msg "[wifi] RSSI 使用兜底估算值: $result" "[warn]"
        echo "$result"; return 0
    fi

    # 全部失败
    echo ""
}


# ----------------------------------------------------------------------
# 移动信号 dBm 读取（多格式兼容）
# ----------------------------------------------------------------------
se_get_mobile_dbm() {
    local reg block dbm
    reg=$(se_dumpsys_cached telephony.registry 2>/dev/null)
    [ -z "$reg" ] && { echo ""; return 0; }

    # 支持 Android 14+ 格式 + 无效值过滤 (2147483647 = Integer.MAX_VALUE)

    # 方法 1: 从卡1 块 (mPhoneId=0) 内取 mDbm（最精确，避免取到卡2 的）
    block=$(echo "$reg" | awk '/mPhoneId=0/{flag=1; next} /mPhoneId=/{flag=0} flag' 2>/dev/null)
    if [ -n "$block" ]; then
        dbm=$(echo "$block" | grep -oE 'mDbm=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
        [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

        dbm=$(echo "$block" | grep -oE 'dbm = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
        [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

        dbm=$(echo "$block" | grep -oE 'mDbm: [-]?[0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
        [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

        dbm=$(echo "$block" | grep 'mSignalStrength' 2>/dev/null | head -1 | grep -oE '[-][0-9]+' | head -1)
        [ -n "$dbm" ] && [ "$dbm" != "-2147483647" ] && { echo "$dbm"; return 0; }
    fi

    # 方法 2: 从第一个 mSignalStrength 块内取 (mSignalStrength 后 30 行)
    block=$(echo "$reg" | awk '/mSignalStrength/{found=1} found{print; if(++count>=30) exit}' 2>/dev/null)
    if [ -n "$block" ]; then
        dbm=$(echo "$block" | grep -oE 'mDbm=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
        [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

        dbm=$(echo "$block" | grep -oE 'dbm = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
        [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

        dbm=$(echo "$block" | grep -oE 'mDbm: [-]?[0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
        [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }
    fi

    # 方法 3: 全局第一个 mDbm= (最后兜底)
    dbm=$(echo "$reg" | grep -oE 'mDbm=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

    dbm=$(echo "$reg" | grep -oE 'dbm = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

    dbm=$(echo "$reg" | grep -oE 'mDbm: [-]?[0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
    [ -n "$dbm" ] && [ "$dbm" != "2147483647" ] && { echo "$dbm"; return 0; }

    dbm=$(echo "$reg" | grep 'mSignalStrength' 2>/dev/null | head -1 | grep -oE '[-][0-9]+' | head -1)
    [ -n "$dbm" ] && [ "$dbm" != "-2147483647" ] && { echo "$dbm"; return 0; }

    # 全部失败
    echo ""
}

se_get_mobile_level() {
    local reg block level
    reg=$(se_dumpsys_cached telephony.registry 2>/dev/null)
    [ -z "$reg" ] && { echo ""; return 0; }

    # 优先采用父级 mSignalStrength.mLevel（系统信号栏显示值，0-4）
    # 不再优先取 mNr 子块 level，因为 NR 子信号等级与整体 mLevel 可能不一致，
    # 会造成"信号越强等级越低"的视觉错乱

    # 方法 1: 从卡1 块 (mPhoneId=0) 内取 mLevel（最精确，避免取到卡2 的）
    block=$(echo "$reg" | awk '/mPhoneId=0/{flag=1; next} /mPhoneId=/{flag=0} flag' 2>/dev/null)
    if [ -n "$block" ]; then
        level=$(echo "$block" | grep -oE 'mLevel=[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
        [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

        level=$(echo "$block" | grep -oE 'mLevel: [0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
        [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

        level=$(echo "$block" | grep -oE 'level = [0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
        [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }
    fi

    # 方法 2: 从第一个 mSignalStrength 块内取 (mSignalStrength 后 20 行)
    block=$(echo "$reg" | awk '/mSignalStrength/{found=1} found{print; if(++count>=20) exit}' 2>/dev/null)
    if [ -n "$block" ]; then
        level=$(echo "$block" | grep -oE 'mLevel=[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
        [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

        level=$(echo "$block" | grep -oE 'mLevel: [0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
        [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

        level=$(echo "$block" | grep -oE 'level = [0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
        [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }
    fi

    # 方法 3: 全局第一个 mLevel= (最后兜底)
    level=$(echo "$reg" | grep -oE 'mLevel=[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

    level=$(echo "$reg" | grep -oE 'mLevel: [0-9]+' 2>/dev/null | head -1 | awk '{print $2}')
    [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

    level=$(echo "$reg" | grep -oE 'level = [0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$level" ] && [ "$level" != "2147483647" ] && { echo "$level"; return 0; }

    echo ""
}

# ----------------------------------------------------------------------
# 5G NR 信号质量读取
# ----------------------------------------------------------------------
# 参考 CellSignalStrengthNr.java:
#   https://android.googlesource.com/platform/frameworks/base.git/+/master/telephony/java/android/telephony/CellSignalStrengthNr.java
# 字段说明:
#   mSsRsrp  = SS-RSRP (同步信号参考功率, 主用, -156~-31 dBm)
#   mCsiRsrp = CSI-RSRP (信道状态参考功率, 辅助, -156~-31 dBm)
#   mSsRsrq  = SS-RSRQ (信号质量, -43~20 dB)
#   mCsiRsrq = CSI-RSRQ (信道状态信号质量)
#   mSsSinr  = SS-SINR (信噪比+干扰, -23~40 dB, 假满格判定关键指标)
#   mCsiSinr = CSI-SINR (信道状态信噪比)
#   mLteRsrp = 4G LTE RSRP (5G 不可用时回退, -140~-44 dBm)

# 5G SS-RSRP 读取（主用信号强度）
se_get_nr_rsrp() {
    local reg result
    reg=$(se_dumpsys_cached telephony.registry 2>/dev/null)

    # 支持 Android 14+ 格式 (无 m 前缀, 等号两边有空格)
    # 真实输出: ssRsrp = -97 ssRsrq = -11 ssSinr = 8 level = 4
    # 模式 1: ssRsrp = -97 (Android 14+ 新格式)
    result=$(echo "$reg" | grep -oE 'ssRsrp = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 2: mSsRsrp=-95 (5G SS-RSRP, AOSP 旧格式)
    result=$(echo "$reg" | grep -oE 'mSsRsrp=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 3: mCsiRsrp=-95 (5G CSI-RSRP, AOSP 标准)
    result=$(echo "$reg" | grep -oE 'mCsiRsrp=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 3b: csiRsrp = -97 (Android 14+ CSI-RSRP 新格式)
    result=$(echo "$reg" | grep -oE 'csiRsrp = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 4: mLteRsrp=-95 (4G LTE RSRP, 5G 不可用时回退)
    result=$(echo "$reg" | grep -oE 'mLteRsrp=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 4b: lteRsrp = -97 (Android 14+ LTE-RSRP 新格式)
    result=$(echo "$reg" | grep -oE 'lteRsrp = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 5: mDbm=-95 (旧 AOSP 兜底)
    result=$(echo "$reg" | grep -oE 'mDbm=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 全部失败
    echo ""
}

# 5G SS-SINR 读取（信噪比, 假满格判定关键指标）
se_get_nr_sinr() {
    local reg result
    reg=$(se_dumpsys_cached telephony.registry 2>/dev/null)

    # 支持 Android 14+ 格式 (无 m 前缀, 等号两边有空格)
    # 真实输出: ssSinr = 8
    # 模式 1: ssSinr = 8 (Android 14+ 新格式)
    result=$(echo "$reg" | grep -oE 'ssSinr = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 2: mSsSinr=13 (5G SS-SINR, AOSP 旧格式)
    result=$(echo "$reg" | grep -oE 'mSsSinr=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 3: mCsiSinr=13 (5G CSI-SINR)
    result=$(echo "$reg" | grep -oE 'mCsiSinr=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 3b: csiSinr = 8 (Android 14+ CSI-SINR 新格式)
    result=$(echo "$reg" | grep -oE 'csiSinr = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 4: mLteRssnr=6 (4G SINR)
    result=$(echo "$reg" | grep -oE 'mLteRssnr=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 4b: lteRssnr = 6 (Android 14+ LTE-SINR 新格式)
    result=$(echo "$reg" | grep -oE 'lteRssnr = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 全部失败
    echo ""
}

# 5G SS-RSRQ 读取（信号质量）
se_get_nr_rsrq() {
    local reg result
    reg=$(se_dumpsys_cached telephony.registry 2>/dev/null)

    # 支持 Android 14+ 格式 (无 m 前缀, 等号两边有空格)
    # 真实输出: ssRsrq = -11
    # 模式 1: ssRsrq = -11 (Android 14+ 新格式)
    result=$(echo "$reg" | grep -oE 'ssRsrq = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 2: mSsRsrq=-10 (5G SS-RSRQ, AOSP 旧格式)
    result=$(echo "$reg" | grep -oE 'mSsRsrq=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 3: mCsiRsrq=-10 (5G CSI-RSRQ)
    result=$(echo "$reg" | grep -oE 'mCsiRsrq=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 3b: csiRsrq = -11 (Android 14+ CSI-RSRQ 新格式)
    result=$(echo "$reg" | grep -oE 'csiRsrq = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 4: mLteRsrq=-10 (4G RSRQ)
    result=$(echo "$reg" | grep -oE 'mLteRsrq=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 模式 4b: lteRsrq = -11 (Android 14+ LTE-RSRQ 新格式)
    result=$(echo "$reg" | grep -oE 'lteRsrq = -?[0-9]+' 2>/dev/null | head -1 | sed 's/.*= *//')
    [ -n "$result" ] && [ "$result" != "2147483647" ] && { echo "$result"; return 0; }

    # 全部失败
    echo ""
}

# ----------------------------------------------------------------------
# 5G 假满格判定
# ----------------------------------------------------------------------
# 判定条件（满足任一即判定为假满格）:
#   1. SS-RSRP ≥ -85（信号强度好）但 Ping > 200ms
#   2. SS-RSRP ≥ -85 但 SS-SINR < 0（信噪比差）
#   3. SS-RSRP ≥ -85 但 Ping 失败（丢包）
# 返回值: 0 = 假满格, 1 = 正常
se_detect_fake_5g() {
    [ "$ENABLE_FAKE_5G_DETECTION" = "true" ] || return 1

    local rsrp sinr ping_ms
    rsrp=$(se_get_nr_rsrp 2>/dev/null)
    sinr=$(se_get_nr_sinr 2>/dev/null)
    ping_ms=$(se_get_ping_ms 2>/dev/null)

    # 空值容错
    [ -z "$rsrp" ] && return 1

    # RSRP 必须为整数
    case "$rsrp" in
        ''|*[!0-9-]*) return 1 ;;
    esac

    # 取绝对值（RSRP 是负数, 越接近 0 越强）
    local abs_rsrp
    if [ "$rsrp" -lt 0 ] 2>/dev/null; then
        abs_rsrp=$((-rsrp))
    else
        abs_rsrp="$rsrp"
    fi

    # 阈值转换: FAKE_5G_RSRP_THRESHOLD 默认 -85, abs 85
    local abs_threshold
    abs_threshold=$(( -FAKE_5G_RSRP_THRESHOLD ))
    [ "$abs_threshold" -le 0 ] 2>/dev/null && abs_threshold=85

    # 仅当 RSRP 强于阈值时才判定（信号差不是假满格, 是真弱）
    if [ "$abs_rsrp" -lt "$abs_threshold" ] 2>/dev/null; then
        # RSRP ≥ -85（信号强度好）

        # 条件 1: Ping 过高
        if [ "$ping_ms" != "?" ] && [ -n "$ping_ms" ]; then
            case "$ping_ms" in
                ''|*[!0-9]*) ;;
                *)
                    if [ "$ping_ms" -gt "$FAKE_5G_PING_THRESHOLD" ] 2>/dev/null; then
                        log_msg "[假满格] RSRP=$rsrp(强) 但 Ping=${ping_ms}ms > ${FAKE_5G_PING_THRESHOLD}ms" "[5g]"
                        return 0
                    fi
                    ;;
            esac
        else
            # 条件 3: Ping 失败（丢包）
            log_msg "[假满格] RSRP=$rsrp(强) 但 Ping 失败(丢包)" "[5g]"
            return 0
        fi

        # 条件 2: SINR 差
        if [ -n "$sinr" ]; then
            case "$sinr" in
                ''|*[!0-9-]*) ;;
                *)
                    if [ "$sinr" -lt "$FAKE_5G_SINR_THRESHOLD" ] 2>/dev/null; then
                        log_msg "[假满格] RSRP=$rsrp(强) 但 SINR=$sinr < $FAKE_5G_SINR_THRESHOLD" "[5g]"
                        return 0
                    fi
                    ;;
            esac
        fi
    fi

    return 1
}

# ----------------------------------------------------------------------
# 公网延迟检测（精简 fallback: 4 次尝试 vs 原 8+ 次）
# ----------------------------------------------------------------------
# 优先 /system/bin/ping 绝对路径（绕过 BusyBox applet 差异）
# ping 全部失败时, 使用 nc 测试 DNS 53 端口可达性
#   - 可达 → 返回 2000（延迟较差但连通）
#   - 彻底不通 → 返回 timeout
se_get_ping_ms() {
    local result

    # 单次 ping 函数：尝试单个 DNS，成功则 stdout 输出延迟，返回 0
    _ping_one() {
        local host="$1"
        local result
        if [ -x /system/bin/ping ]; then
            result=$(/system/bin/ping -c 1 -W 2 "$host" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
            [ -n "$result" ] && echo "$result" && return 0
        fi
        result=$(ping -c 1 -W 2 "$host" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
        [ -n "$result" ] && echo "$result" && return 0
        return 1
    }

    # 尝试 1: 阿里 DNS
    result=$(_ping_one 223.5.5.5) && [ -n "$result" ] && echo "$result" && return 0
    # 尝试 2: 腾讯 DNS
    result=$(_ping_one 119.29.29.29) && [ -n "$result" ] && echo "$result" && return 0
    # 尝试 3: 114 DNS
    result=$(_ping_one 114.114.114.114) && [ -n "$result" ] && echo "$result" && return 0

    # 尝试 4: 本地网关（后台环境兜底）
    local gateway
    gateway=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        result=$(_ping_one "$gateway") && [ -n "$result" ] && echo "$result" && return 0
    fi

    # ping 全部失败时, 使用 nc 测试 DNS 53 端口可达性
    if command -v nc >/dev/null 2>&1; then
        if nc -w 2 -z 223.5.5.5 53 2>/dev/null || \
           nc -w 2 -z 119.29.29.29 53 2>/dev/null; then
            echo "2000"
            return 0
        fi
    fi

    echo "timeout"
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
    if [ -z "$rssi" ] || [ "$rssi" = "?" ]; then
        echo "unknown"
        return 0
    fi

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

# ----------------------------------------------------------------------
# 4 级综合判定（含 SINR 维度）
# ----------------------------------------------------------------------
#   strong:  RSSI ≥ -60 且 Ping < 80ms 且 SINR ≥ 10
#   normal:  RSSI -60~-75 或 Ping 80~150ms
#   weak:    RSSI -75~-90 或 Ping 150~200ms
#   critical: RSSI < -90 或 Ping > 200ms 或 SINR < 0
se_overall_level() {
    local net_type="$1" wifi_lvl="$2" mobile_lvl="$3" ping_ms="$4"
    local nr_sinr="${5:-}"

    local ping_critical=0 ping_bad=0
    if [ "$ENABLE_PING_FEEDBACK" = "true" ] && [ "$ping_ms" != "?" ] && [ -n "$ping_ms" ]; then
        case "$ping_ms" in
            ''|*[!0-9]*) ;;
            *)
                [ "$ping_ms" -ge "$PING_BAD_MS" ] 2>/dev/null && ping_critical=1
                [ "$ping_ms" -ge "$PING_GOOD_MS" ] 2>/dev/null && [ "$ping_ms" -lt "$PING_BAD_MS" ] 2>/dev/null && ping_bad=1
                ;;
        esac
    fi

    # SINR 维度判定
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

    # SINR < 0 直接降级到 critical
    if [ "$sinr_critical" = "1" ]; then
        echo "critical"
        return
    fi

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

    # 默认值兜底
    interval="${MONITOR_NORMAL_INTERVAL:-120}"
    scan_ms=15000
    bad_rssi=-88
    mobile_ka=1
    ping_chk=1

    case "$level" in
        strong)
            interval="${MONITOR_MAX_INTERVAL:-120}"; scan_ms=30000; bad_rssi=-70;  mobile_ka=1; ping_chk=0 ;;
        normal)
            interval="${MONITOR_NORMAL_INTERVAL:-120}"; scan_ms=15000; bad_rssi=-88;  mobile_ka=1; ping_chk=1 ;;
        weak)
            interval="${MONITOR_MIN_INTERVAL:-120}"; scan_ms=10000; bad_rssi=-95;  mobile_ka=1; ping_chk=1 ;;
        critical)
            interval="${MONITOR_MIN_INTERVAL:-120}"; scan_ms=8000;  bad_rssi=-100; mobile_ka=1; ping_chk=1 ;;
        *)
            interval="${MONITOR_NORMAL_INTERVAL:-120}"; scan_ms=15000; bad_rssi=-88;  mobile_ka=1; ping_chk=1 ;;
    esac

    # 动态插值前严格校验
    if [ "$ENABLE_DYNAMIC_PARAMS" = "true" ] && [ "$level" != "critical" ]; then
        case "$rssi_abs" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$rssi_abs" -gt 0 ] 2>/dev/null; then
                    local rssi_clamped
                    rssi_clamped=$(se_clamp "$rssi_abs" 40 100)
                    local _new_scan _new_bad
                    _new_scan=$(se_lerp "$rssi_clamped" 40 30000 100 8000)
                    _new_bad=$(se_lerp "$rssi_clamped" 40 -65 100 -100)
                    [ -n "$_new_scan" ] && scan_ms="$_new_scan"
                    [ -n "$_new_bad" ] && bad_rssi="$_new_bad"
                fi
                ;;
        esac
    fi

    # 最终输出前再次确保所有字段非空
    [ -z "$interval" ] && interval=120
    [ -z "$scan_ms" ] && scan_ms=15000
    [ -z "$bad_rssi" ] && bad_rssi=-88
    [ -z "$mobile_ka" ] && mobile_ka=1
    [ -z "$ping_chk" ] && ping_chk=1

    echo "${interval} ${scan_ms} ${bad_rssi} ${mobile_ka} ${ping_chk}"
    return 0
}

# ----------------------------------------------------------------------
# 模块自检
# ----------------------------------------------------------------------
# 修复: MODDIR_ROOT 未解析时 check_dir 为空导致 customize.sh 误报缺失
# 增强: 新增 Android 版本、命令可用性、5G 信号质量检测
se_self_check() {
    echo "=== 网络增强 v${SE_VERSION} 自检 ==="
    echo ""

    # check_dir 无效时用 pwd 兜底（修复 customize.sh 误报缺失 bug）
    local check_dir="${MODDIR_ROOT:-${MODPATH:-${MODDIR:-}}}"
    if [ -z "$check_dir" ] || [ ! -d "$check_dir" ]; then
        check_dir="$(pwd 2>/dev/null)"
    fi

    echo "[环境]"
    echo "  引擎       : $(detect_env)"
    echo "  AXERON     : ${AXERON:-未设置}"
    echo "  AXERONVER  : ${AXERONVER:-未知}"
    echo "  AXERONDIR  : ${AXERONDIR:-未设置}"
    echo "  MODPATH    : ${MODPATH:-未设置}"
    echo "  MODDIR_ROOT: ${MODDIR_ROOT:-未解析}"
    echo "  pwd        : $(pwd 2>/dev/null)"
    echo "  \$0         : ${0:-空}"
    echo ""

    # 重新解析一次，确认 MODDIR_ROOT 有效
    if [ -z "${MODDIR_ROOT:-}" ] || [ ! -d "${MODDIR_ROOT:-}" ]; then
        echo "[!] MODDIR_ROOT 无效，尝试重新解析..."
        MODDIR_ROOT="$(se_resolve_moddir 2>/dev/null)" || MODDIR_ROOT=""
        MODDIR="$MODDIR_ROOT"
        if [ -n "$MODDIR_ROOT" ]; then
            check_dir="$MODDIR_ROOT"
        fi
    fi

    echo "[关键文件] (检查目录: $check_dir)"
    if [ -n "$check_dir" ] && [ -d "$check_dir" ]; then
        for f in module.prop customize.sh post-fs-data.sh service.sh action.sh uninstall.sh config.sh LICENSE; do
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

    echo "[Android 版本]"
    local api
    api=$(se_get_api)
    echo "  API 级别    : ${api:-未知}"
    if se_is_android_14_plus; then
        echo "  兼容性      : OK Android 14+ 完全支持"
    else
        echo "  兼容性      : WARN 低于 Android 14, 部分功能可能受限"
    fi
    echo ""

    echo "[命令可用性]"
    if cmd wifi status >/dev/null 2>&1; then
        echo "  cmd wifi status      : OK 可用"
    else
        echo "  cmd wifi status      : FAIL 不可用"
    fi
    if cmd netpolicy list restrict-background-whitelist >/dev/null 2>&1; then
        echo "  cmd netpolicy        : OK 可用"
    else
        echo "  cmd netpolicy        : FAIL 不可用"
    fi
    if cmd connectivity get-airplane-mode >/dev/null 2>&1; then
        echo "  cmd connectivity     : OK 可用"
    else
        echo "  cmd connectivity     : FAIL 不可用"
    fi
    if cmd notification list >/dev/null 2>&1; then
        echo "  cmd notification     : OK 可用"
    else
        echo "  cmd notification     : FAIL 不可用"
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
    echo "  preferred_network_mode          = $(se_get global preferred_network_mode)"
    echo ""

    echo "[动态参数引擎]"
    echo "  ENABLE_DYNAMIC_PARAMS   = ${ENABLE_DYNAMIC_PARAMS}"
    echo "  ENABLE_PING_FEEDBACK    = ${ENABLE_PING_FEEDBACK}"
    echo "  ENABLE_OEM_COMPAT       = ${ENABLE_OEM_COMPAT}"
    echo "  ENABLE_FAKE_5G_DETECTION = ${ENABLE_FAKE_5G_DETECTION}"
    echo "  MONITOR_NORMAL_INTERVAL = ${MONITOR_NORMAL_INTERVAL}s (统一120s)"
    echo ""

    echo "[实时信号]"
    local rssi dbm ping_ms nr_rsrp nr_sinr nr_rsrq
    rssi=$(se_get_wifi_rssi)
    dbm=$(se_get_mobile_dbm)
    ping_ms=$(se_get_ping_ms)
    nr_rsrp=$(se_get_nr_rsrp)
    nr_sinr=$(se_get_nr_sinr)
    nr_rsrq=$(se_get_nr_rsrq)
    echo "  WiFi RSSI      : ${rssi:-未连接}"
    echo "  移动 dBm       : ${dbm:-未检测}"
    echo "  NR RSRP        : ${nr_rsrp:-未检测} dBm"
    echo "  NR RSRQ        : ${nr_rsrq:-未检测} dB"
    echo "  NR SINR        : ${nr_sinr:-未检测} dB"
    echo "  公网延迟       : ${ping_ms} ms"
    if se_detect_fake_5g; then
        echo "  假满格判定     : WARN 检测到 5G 假满格"
    else
        echo "  假满格判定     : OK 正常"
    fi
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
