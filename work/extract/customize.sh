#!/system/bin/sh
# customize.sh — 卫星地球 Pro v6.3.0 安装脚本
# 本脚本会被 source（不是执行），不能用 exit，要用 abort

SKIPUNZIP=0

# v6.3.0: MODPATH 健壮性校验
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
            /data/user_de/0/com.android.shell/axeron/plugins/Satellite_Earth \
            /data/user_de/0/android/axeron/plugins/Satellite_Earth \
            /data/adb/modules/Satellite_Earth; do
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
ui_print "  卫星地球 Pro v6.3.0"
ui_print "  AxManager 免Root 网络优化"
ui_print "  多品牌兼容版（路径修复）"
ui_print "***************************************"
ui_print ""
ui_print "  作者 : 寒碑听风"
ui_print "  协议 : MIT"
ui_print ""

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

mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
carrier_name=$(getprop gsm.sim.operator.alpha 2>/dev/null)
ui_print "  → SIM 运营商: ${carrier_name:-无} (${mccmnc:-未知})"
ui_print ""

ui_print "---------------------------------------"
ui_print "  OEM 兼容性预检"
ui_print "---------------------------------------"

case "$_brand_norm" in
    xiaomi)
        ui_print "  → 小米系 (MIUI/HyperOS) 检测"
        ui_print "    [替换] nr_sa_mode → nr_mode"
        ui_print "    [替换] data_stall_alarm_* → MIUI 私有键"
        ui_print "    [跳过] wifi_pno_frequency_threshold"
        ui_print "    [跳过] wifi_recovery_state"
        ;;
    vivo)
        ui_print "  → vivo/步步高系 (Funtouch/OriginOS) 检测"
        ui_print "    [跳过] nr_sa_mode (会导致 telephony 崩溃)"
        ui_print "    [跳过] enable_nr_dc (部分机型 modem 重启)"
        ui_print "    [跳过] data_stall_alarm_* 系列"
        ui_print "    [跳过] wifi_enhanced_mac_randomization_enabled"
        ;;
    samsung)
        ui_print "  → 三星 (OneUI) 检测"
        ui_print "    [跳过] nr_sa_mode/enable_nr_dc/endc_capability"
        ui_print "    [跳过] wifi_max_dwell_time_ms"
        ;;
    huawei|honor)
        ui_print "  → 华为/荣耀 (EMUI/MagicOS) 检测"
        ui_print "    [跳过] 全部 5G NR 键"
        ui_print "    [跳过] wifi_persistent_group_remove_delay_ms"
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
ui_print "  v6.3.0 路径修复要点"
ui_print "---------------------------------------"
ui_print ""
ui_print "  [修复] action.sh 用 pwd 替代 \${0%/*}"
ui_print "         原因: AxManager 调用 action.sh 时"
ui_print "         执行 cd \"<pluginPath>\"; sh ./action.sh"
ui_print "         导致 \$0 = \"./action.sh\", \${0%/*} = \".\""
ui_print "         一旦脚本内部 cd 就失效"
ui_print "  [修复] 全部脚本统一 bootstrap 模式"
ui_print "  [修复] se_put 错误吞没用 if/else 替代 || true"
ui_print "  [修复] dumpsys 解析多 ROM 兼容"
ui_print "         (mRssi/mDbm/mLevel 多模式匹配)"
ui_print "  [新增] AXERONDIR 环境变量推导路径"
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

for _f in config.sh module.prop system.prop; do
    if [ -f "$MODPATH/$_f" ]; then
        set_perm "$MODPATH/$_f" 0 0 0644
    fi
done

ui_print "  [OK] 权限已设置"
ui_print ""

ui_print "***************************************"
ui_print "  ✓ 安装成功 (v6.3.0 多品牌兼容版)"
ui_print "***************************************"
ui_print ""
ui_print "  日志路径: /data/local/tmp/satellite_earth.log"
ui_print "  用户配置: \$MODPATH/config.sh"
ui_print "  OEM 兼容开关: ENABLE_OEM_COMPAT=true"
ui_print "  WebUI: 在 AxManager 中点击模块'界面'"
ui_print ""
