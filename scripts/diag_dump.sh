#!/system/bin/sh
# diag_dump.sh — 网络增强 诊断数据抓取脚本
#
# 用途：抓取设备真实的 dumpsys/cmd/ping 原始输出，用于修正正则匹配规则
# 用法：sh diag_dump.sh
# 输出：屏幕显示 + 日志文件 /data/local/tmp/network_enhance_diag.txt

DIAG_FILE="/data/local/tmp/network_enhance_diag.txt"

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

echo "=========================================="
echo "  网络增强 诊断数据抓取"
echo "=========================================="
echo ""

# 尝试加载 common.sh 以使用 se_ci_detect / se_ci_log
_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    for _p in \
        /data/user_de/0/com.android.shell/axeron/plugins/Network_Enhance \
        /data/user_de/0/android/axeron/plugins/Network_Enhance \
        /data/adb/modules/Network_Enhance; do
        [ -f "$_p/scripts/common.sh" ] 2>/dev/null && { echo "$_p/scripts/common.sh"; return 0; }
    done
    return 1
}
_se_common=$(_se_find_common 2>/dev/null)
if [ -n "$_se_common" ]; then
    . "$_se_common" 2>/dev/null
    se_ci_detect 2>/dev/null
fi
unset _se_common
# 保留 _se_find_common 供后续 section 7 复用

if [ "$(type -t se_ci_log 2>/dev/null)" = "function" ]; then
    se_ci_log "diag_dump.sh" "diag_dump.sh 启动"
fi

# 清空旧日志
> "$DIAG_FILE"

log_section() {
    local title="$1"
    se_ci_log "diag_dump.sh" "阶段: $title"
    echo ""
    echo "=========================================="
    echo "$title"
    echo "=========================================="
    echo ""
    # 同时写入屏幕和日志文件
    echo "" >> "$DIAG_FILE"
    echo "==========================================" >> "$DIAG_FILE"
    echo "$title" >> "$DIAG_FILE"
    echo "==========================================" >> "$DIAG_FILE"
    echo "" >> "$DIAG_FILE"
}

run_cmd() {
    local cmd="$1"
    echo "[CMD] $cmd"
    echo ""
    echo "[CMD] $cmd" >> "$DIAG_FILE"
    echo "" >> "$DIAG_FILE"
    # 执行并 tee 到日志
    eval "$cmd" 2>&1 | tee -a "$DIAG_FILE"
    echo "" | tee -a "$DIAG_FILE"
    echo "----------------------------------------" | tee -a "$DIAG_FILE"
    echo "" | tee -a "$DIAG_FILE"
}

# ===============================
# 1. 设备基础信息
# ===============================
log_section "1. 设备基础信息"
echo "品牌: $(getprop ro.product.brand)"
echo "型号: $(getprop ro.product.model)"
echo "Android: $(getprop ro.build.version.release) (API $(getprop ro.build.version.sdk))"
echo "ROM: $(getprop ro.build.display.id)"
echo "硬件: $(getprop ro.hardware)"
echo "SIM 运营商: $(getprop gsm.sim.operator.alpha) ($(getprop gsm.sim.operator.numeric))"
echo "网络类型: $(getprop gsm.network.type)"
{
    echo "品牌: $(getprop ro.product.brand)"
    echo "型号: $(getprop ro.product.model)"
    echo "Android: $(getprop ro.build.version.release) (API $(getprop ro.build.version.sdk))"
    echo "ROM: $(getprop ro.build.display.id)"
    echo "硬件: $(getprop ro.hardware)"
    echo "SIM 运营商: $(getprop gsm.sim.operator.alpha) ($(getprop gsm.sim.operator.numeric))"
    echo "网络类型: $(getprop gsm.network.type)"
} >> "$DIAG_FILE"

# ===============================
# 2. dumpsys telephony.registry 完整 mSignalStrength 区域
# ===============================
log_section "2. dumpsys telephony.registry (信号强度原始输出)"
run_cmd "dumpsys telephony.registry 2>/dev/null | grep -iE 'mSignalStrength|SignalStrength|CellSignalStrengthNr|mLevel|mLteRsrp|mSsRsrp|mCsiRsrp|mSsSinr|mCsiSinr|mSsRsrq|mCsiRsrq|mLteRsrq|mLteRssnr|mDbm|mRssi' | head -50"

# ===============================
# 2b. dumpsys telephony.registry 完整输出前 100 行（兜底，避免 grep 漏掉字段）
# ===============================
log_section "2b. dumpsys telephony.registry 前 100 行（兜底原始输出）"
run_cmd "dumpsys telephony.registry 2>/dev/null | head -100"

# ===============================
# 3. cmd wifi status 完整输出
# ===============================
log_section "3. cmd wifi status 完整输出"
run_cmd "cmd wifi status 2>/dev/null"

# ===============================
# 3b. dumpsys wifi 中 RSSI/SSID/频率相关字段
# ===============================
log_section "3b. dumpsys wifi RSSI/SSID/频率字段"
run_cmd "dumpsys wifi 2>/dev/null | grep -iE 'mRssi|RSSI|mWifiInfo|WifiInfo|SSID|mFrequency|frequency|mLinkSpeed|Link speed' | head -30"

# ===============================
# 4. dumpsys connectivity 网络制式
# ===============================
log_section "4. dumpsys connectivity 网络制式"
run_cmd "dumpsys connectivity 2>/dev/null | grep -iE 'NetworkAgentInfo|Active default|CONNECTED|VALIDATED' | head -20"

# ===============================
# 5. ping 测试
# ===============================
log_section "5. ping 测试（百度）"
run_cmd "ping -c 1 -W 2 www.baidu.com 2>&1"

# ===============================
# 5b. ping 测试（阿里 DNS）
# ===============================
log_section "5b. ping 测试（阿里 DNS 223.5.5.5）"
run_cmd "ping -c 1 -W 2 223.5.5.5 2>&1"

# ===============================
# 6. 当前 settings 关键值（用于对照）
# ===============================
log_section "6. 当前 settings 关键值"
echo "preferred_network_mode  = $(settings get global preferred_network_mode)"
echo "preferred_network_mode1 = $(settings get global preferred_network_mode1)"
echo "mobile_data_always_on   = $(settings get global mobile_data_always_on)"
echo "wifi_scan_throttle_enabled = $(settings get global wifi_scan_throttle_enabled)"
echo "private_dns_mode        = $(settings get global private_dns_mode)"
echo "private_dns_spec        = $(settings get global private_dns_spec)"
{
    echo "preferred_network_mode  = $(settings get global preferred_network_mode)"
    echo "preferred_network_mode1 = $(settings get global preferred_network_mode1)"
    echo "mobile_data_always_on   = $(settings get global mobile_data_always_on)"
    echo "wifi_scan_throttle_enabled = $(settings get global wifi_scan_throttle_enabled)"
    echo "private_dns_mode        = $(settings get global private_dns_mode)"
    echo "private_dns_spec        = $(settings get global private_dns_spec)"
} >> "$DIAG_FILE"

# ===============================
# 7. 模块当前解析结果（对照真实输出，定位差异）
# ===============================
log_section "7. 模块当前解析结果（对照参考）"

# 复用 bootstrap 阶段的 _se_find_common（已定义，含完整路径探测）
_se_common=$(_se_find_common 2>/dev/null)
if [ -n "$_se_common" ]; then
    . "$_se_common" 2>/dev/null
    echo "common.sh 路径: $_se_common"
    echo "WiFi RSSI (模块解析) : $(se_get_wifi_rssi 2>/dev/null)"
    echo "移动 dBm (模块解析)  : $(se_get_mobile_dbm 2>/dev/null)"
    echo "移动 Level (模块解析): $(se_get_mobile_level 2>/dev/null)"
    echo "NR RSRP (模块解析)   : $(se_get_nr_rsrp 2>/dev/null)"
    echo "NR RSRQ (模块解析)   : $(se_get_nr_rsrq 2>/dev/null)"
    echo "NR SINR (模块解析)   : $(se_get_nr_sinr 2>/dev/null)"
    echo "Ping ms (模块解析)   : $(se_get_ping_ms 2>/dev/null)"
    echo "网络类型 (模块解析)  : $(se_detect_network_type 2>/dev/null)"
    {
        echo "common.sh 路径: $_se_common"
        echo "WiFi RSSI (模块解析) : $(se_get_wifi_rssi 2>/dev/null)"
        echo "移动 dBm (模块解析)  : $(se_get_mobile_dbm 2>/dev/null)"
        echo "移动 Level (模块解析): $(se_get_mobile_level 2>/dev/null)"
        echo "NR RSRP (模块解析)   : $(se_get_nr_rsrp 2>/dev/null)"
        echo "NR RSRQ (模块解析)   : $(se_get_nr_rsrq 2>/dev/null)"
        echo "NR SINR (模块解析)   : $(se_get_nr_sinr 2>/dev/null)"
        echo "Ping ms (模块解析)   : $(se_get_ping_ms 2>/dev/null)"
        echo "网络类型 (模块解析)  : $(se_detect_network_type 2>/dev/null)"
    } >> "$DIAG_FILE"
else
    echo "common.sh 未找到，跳过模块解析对照"
    echo "common.sh 未找到，跳过模块解析对照" >> "$DIAG_FILE"
fi

echo ""
echo "=========================================="
echo "  诊断完成"
echo "=========================================="
echo ""
echo "完整日志已保存到: $DIAG_FILE"
echo ""
echo "请将日志内容发送给开发者以修正正则匹配规则"
echo "获取日志命令:"
echo "  cat $DIAG_FILE"
echo "  或在 WebUI 终端执行: cat $DIAG_FILE"

exit 0
