#!/system/bin/sh
# customize.sh — 网络增强 安装脚本
# 本脚本会被 source（不是执行），不能用 exit，要用 abort

SKIPUNZIP=0

# MODPATH 健壮性校验
if [ -z "${MODPATH:-}" ] || [ ! -d "$MODPATH" ]; then
    ui_print "  [!] MODPATH 未设置或不存在，尝试兜底解析..."
    if [ -n "${0:-}" ] && echo "$0" | grep -q '/' 2>/dev/null; then
        _candidate="${0%/*}"
        if [ -f "$_candidate/module.prop" ] 2>/dev/null; then
            MODPATH="$_candidate"
            ui_print "  [OK] MODPATH 兜底解析成功: $MODPATH"
        fi
    fi
    if [ -z "${MODPATH:-}" ] || [ ! -d "$MODPATH" ]; then
        for _p in \
            /data/user_de/0/com.android.shell/axeron/plugins/Network_Enhance \
            /data/user_de/0/android/axeron/plugins/Network_Enhance \
            /data/adb/modules/Network_Enhance; do
            if [ -f "$_p/module.prop" ] 2>/dev/null; then
                MODPATH="$_p"
                ui_print "  [OK] MODPATH 命中已知路径: $MODPATH"
                break
            fi
        done
    fi
    if [ -z "${MODPATH:-}" ] || [ ! -d "$MODPATH" ]; then
        ui_print "  [FAIL] 无法解析 MODPATH，安装中止"
        abort "MODPATH 解析失败"
    fi
fi

ui_print "***************************************"
ui_print "  网络增强"
ui_print "  AxManager 免Root 网络优化"
ui_print "  5G假满格自救 + 4G防跳频 + 多品牌兼容"
ui_print "***************************************"
ui_print ""
ui_print "  作者 : 寒碑听风"
ui_print "  → 协议 : MIT"
ui_print ""

# 加载 common.sh（自动执行 CI 调试模式检测 + config/oem 初始化）
_se_ci_ver=$(grep '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2)
. "$MODPATH/scripts/common.sh"
se_ci_log "customize.sh" "customize.sh 启动 | version=$_se_ci_ver"

ui_print "---------------------------------------"
ui_print "  运行环境与厂商探测"
ui_print "---------------------------------------"

if [ "$AXERON" = "true" ]; then
    ui_print "  → 引擎      : AxManager (ADB 免Root)"
    ui_print "  → 服务器版本: ${AXERONVER:-unknown}"
elif [ -d "/data/adb/ksu" ] 2>/dev/null; then
    ui_print "  → 引擎      : KernelSU (Root)"
elif [ -d "/data/adb/magisk" ] 2>/dev/null; then
    ui_print "  → 引擎      : Magisk (Root)"
elif [ -d "/data/adb/ap" ] 2>/dev/null; then
    ui_print "  → 引擎      : APatch (Root)"
else
    ui_print "  → 引擎      : 未知"
fi

ui_print "  → 设备      : $(getprop ro.product.model)"
ui_print "  → 厂商      : $(getprop ro.product.brand)"
ui_print "  → Android   : $(getprop ro.build.version.release) (API ${API:-?})"
ui_print "  → CPU 架构  : ${ARCH:-?} (64位: ${IS64BIT:-?})"

_brand=$(getprop ro.product.brand 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
case "$_brand" in
    redmi|poco)         _brand_norm="xiaomi" ;;
    oneplus|realme)     _brand_norm="oppo" ;;
    iqoo|bbk)           _brand_norm="vivo" ;;
    *)                  _brand_norm="$_brand" ;;
esac
ui_print "  → 品牌归一化: $_brand_norm"

_hw=$(getprop ro.hardware 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
case "$_hw" in
    *qcom*|*msm*|*sm*)      _soc="qualcomm" ;;
    *mt*|*mediatek*|*mtk*)  _soc="mediatek" ;;
    *kirin*|*hi*)           _soc="hisilicon" ;;
    *exynos*)               _soc="exynos" ;;
    *)                      _soc="unknown" ;;
esac
ui_print "  → 芯片平台  : $_soc"
se_ci_log "customize.sh" "OEM 预检 | brand=$_brand_norm soc=$_soc"

mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
carrier_name=$(getprop gsm.sim.operator.alpha 2>/dev/null)
ui_print "  → SIM 运营商: ${carrier_name:-无} (${mccmnc:-未知})"
se_ci_log "customize.sh" "运营商预检 | mccmnc=$mccmnc carrier=$carrier_name"
ui_print ""

ui_print "---------------------------------------"
ui_print "  OEM 兼容性预检"
ui_print "---------------------------------------"

case "$_brand_norm" in
    xiaomi)
        ui_print "  → 小米系 (MIUI/HyperOS) 检测"
        ui_print "    [替换] nr_sa_mode → nr_mode"
        ui_print "    [替换] data_stall_alarm_* → MIUI 私有键"
        ui_print "    [替换] mobile_data_auto_handover → auto_switch"
        ui_print "    [跳过] wifi_pno_frequency_threshold"
        ui_print "    [跳过] wifi_recovery_state"
        ui_print "    [OK]   preferred_network_mode 可用"
        ;;
    vivo)
        ui_print "  → vivo/步步高系 (Funtouch/OriginOS) 检测"
        ui_print "    [跳过] nr_sa_mode (会导致 telephony 崩溃)"
        ui_print "    [跳过] enable_nr_dc (部分机型 modem 重启)"
        ui_print "    [跳过] data_stall_alarm_* 系列"
        ui_print "    [跳过] wifi_enhanced_mac_randomization_enabled"
        ui_print "    [OK]   preferred_network_mode 可用"
        ;;
    samsung)
        ui_print "  → 三星 (OneUI) 检测"
        ui_print "    [跳过] nr_sa_mode/enable_nr_dc/endc_capability"
        ui_print "    [跳过] wifi_max_dwell_time_ms"
        ui_print "    [WARN] preferred_network_mode 部分版本会忽略 (启用验证)"
        ;;
    huawei|honor)
        ui_print "  → 华为/荣耀 (EMUI/MagicOS/HarmonyOS) 检测"
        ui_print "    [跳过] 全部 5G NR 键 (避免崩溃)"
        ui_print "    [跳过] wifi_persistent_group_remove_delay_ms"
        ui_print "    [OK]   preferred_network_mode 可用 (启用写入验证)"
        ;;
    oppo)
        ui_print "  → OPPO 系 (ColorOS/OxygenOS/RealmeUI) 检测"
        ui_print "    全部键可安全写入（主测试环境）"
        ;;
    *)
        ui_print "  → 未知厂商: $_brand_norm"
        ui_print "    采用保守模式：全部 AOSP 标准键可写"
        ;;
esac
ui_print ""

ui_print "---------------------------------------"
ui_print "  运营商默认值预检 (S3 修正)"
ui_print "---------------------------------------"
case "$mccmnc" in
    46011|46012)        ui_print "  → 电信: preferred_network_mode=27 (NR/LTE/CDMA/EvDo/GSM/WCDMA)" ;;
    46001|46006|46009)  ui_print "  → 联通: preferred_network_mode=26 (NR/LTE/GSM/WCDMA)" ;;
    46000|46002|46004|46007|46008|46013|46015|46017) ui_print "  → 移动: preferred_network_mode=32 (NR/LTE/TD-SCDMA/GSM/WCDMA)" ;;
    46020)              ui_print "  → 广电: preferred_network_mode=33 (全制式含5G)" ;;
    *)                  ui_print "  → 未识别运营商, 将使用默认值 26" ;;
esac
ui_print ""

ui_print "---------------------------------------"
ui_print "  关键特性"
ui_print "---------------------------------------"
ui_print ""
ui_print "  [新增] 5G 假满格自动降级 (RSRP+SINR+Ping 三维度)"
ui_print "  [新增] 防振荡冷却 (降级后强制保持 30 分钟)"
ui_print "  [新增] 游戏模式锁定 LTE Only (mode=11 + ENDC=0)"
ui_print "  [新增] Data Saver 禁后台抢带宽 (cmd netpolicy)"
ui_print "  [新增] 智能 DNS 选择 (ping 测试选最优 DoT)"
ui_print "  [新增] 华为/荣耀/三星 PNM 写入验证机制"
ui_print "  [新增] 无网络死锁回退 (4G 无网时恢复 5G)"
ui_print "  [修正] 运营商默认值 (电信27/移动32/广电33)"
ui_print "  [修正] customize.sh 自检误报缺失 bug"
ui_print "  [移除] system.prop (persist.* 免Root不生效)"
ui_print "  [统一] 检测间隔 120 秒 (所有等级)"
ui_print "  [统一] 命名 network_enhance"
ui_print ""

ui_print "---------------------------------------"
ui_print "  设置文件权限"
ui_print "---------------------------------------"

if [ -d "$MODPATH/scripts" ]; then
    set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
    ui_print "  [OK] scripts/ 权限已设置"
else
    ui_print "  [!] scripts/ 目录不存在，跳过"
fi

if [ -d "$MODPATH/webroot" ]; then
    set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
    ui_print "  [OK] webroot/ 权限已设置"
else
    ui_print "  [!] webroot/ 目录不存在，跳过"
fi

for _f in post-fs-data.sh service.sh uninstall.sh action.sh customize.sh; do
    if [ -f "$MODPATH/$_f" ]; then
        set_perm "$MODPATH/$_f" 0 0 0755
    fi
done

for _f in config.sh module.prop; do
    if [ -f "$MODPATH/$_f" ]; then
        set_perm "$MODPATH/$_f" 0 0 0644
    fi
done

# 确认 system.prop 已移除
if [ -f "$MODPATH/system.prop" ]; then
    ui_print "  [WARN] 检测到 system.prop 残留，删除中..."
    rm -f "$MODPATH/system.prop" 2>/dev/null
    ui_print "  [OK] system.prop 已移除（persist.* 免Root不生效）"
else
    ui_print "  [OK] system.prop 不存在（已正确移除）"
fi

ui_print "  [OK] 权限已设置"
se_ci_log "customize.sh" "权限设置完成"
ui_print ""

ui_print "***************************************"
ui_print "  ✓ 安装成功 (网络增强)"
ui_print "***************************************"
ui_print ""
ui_print "  日志路径: /data/local/tmp/network_enhance.log"
ui_print "  用户配置: \$MODPATH/config.sh"
ui_print "  OEM 兼容开关: ENABLE_OEM_COMPAT=true"
ui_print "  WebUI: 在 AxManager 中点击模块'界面'"
ui_print ""
ui_print "  注意: 重启后 AxManager 需重新激活"
ui_print "  注意: 完全禁用 4G+ 载波聚合需 Root"
ui_print "        本模块通过锁定 LTE 间接降低跳频概率"
ui_print ""

se_ci_log "customize.sh" "安装完成"
