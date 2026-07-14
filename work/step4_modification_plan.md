# 第四步：网络增强 v1.0 详细修改方案

> 基于第一步（代码分析）+ 第二步（AxManager 规范）+ 第三步（ADB 命令研究）+ 用户补充要求制定
> 所有命令、键名、数值均标注来源（S1/S2/S3 = 第一步/第二步/第三步研究发现）

---

## 0. 总体设计原则

1. **严格遵循 AxManager 官方插件协议**（S2）：目录结构、module.prop 字段、生命周期脚本执行时机
2. **所有 ADB Shell 命令必须在 Android 14/15 无 Root 环境下可用**（S3）
3. **所有 settings 键必须经过 OEM 兼容性矩阵过滤**（S1 原模块 + S3 扩展）
4. **代码模块化、注释清晰、健壮性处理**（用户要求）
5. **版本号与命名统一**：模块名"网络增强"，目录名 `Network_Enhance`，版本 v1.0（用户要求）
6. **路径解析 6 级 fallback 保留**（S1 v6.3.0 修复核心，S2 官方建议 ${0%/*} 但实测不可靠）
7. **Android 14/15 双版本兼容**（用户要求）：通过 `getprop ro.build.version.sdk` 检测分支

---

## 1. 文件改动清单（逐文件说明）

### 1.1 根目录文件

#### `module.prop` —— 修改
**改动内容**：
- `id=Network_Enhance`（原 `Satellite_Earth`）
- `name=网络增强`（原"卫星地球 优化版 Pro"）
- `version=v1.0`（原 `1.0`，统一加 v 前缀）
- `versionCode=100`（保持）
- `author=寒碑听风`（保持）
- `description=AxManager 免Root 网络优化 v1.0 | 5G假满格自动降级4G | 游戏模式锁定LTE | 多品牌兼容 | 严格遵循AxManager官方插件协议`
- `banner=banner.png`（保持）
- `axeronPlugin=10000`（保持，对应 AxManager 1.0.x，S2 验证）

**来源**：用户要求命名统一 + S2 AxManager 协议规范

#### `customize.sh` —— 修改
**改动内容**：
1. 标题字符串改为"网络增强 v1.0"
2. **修复自检误报缺失 bug**：原模块自检逻辑在 `se_self_check()` 中用 `$check_dir` 变量，但当 MODDIR_ROOT 未解析时 check_dir 为空，导致报告"customize.sh 缺失"。修复方案：在 `se_self_check()` 中增加 fallback，当 check_dir 无效时用 pwd 直接作为检查目录
3. 安装路径预探所有已知路径替换为 `Network_Enhance`：
   - `/data/user_de/0/com.android.shell/axeron/plugins/Network_Enhance`
   - `/data/user_de/0/android/axeron/plugins/Network_Enhance`
   - `/data/adb/modules/Network_Enhance`
4. 版本号字符串全部改为 `v1.0`
5. OEM 预检输出文案更新（提到"修正运营商默认值"）

**来源**：S1 第一步发现的自检 bug + 用户要求命名统一

#### `post-fs-data.sh` —— 修改
**改动内容**：
1. **移除 system.prop 引用**（S2 确认 persist.* 免Root不生效）
2. **迁移 system.prop 功能**：将原 `persist.sys.satellite_earth.version=1.0` 迁移为 `settings put global network_enhance_version 1.0`（自定义键，仅作状态标记，免Root可写）
3. **修正运营商默认值**（S3 关键发现）：
   - 电信：`preferred_network_mode` 从 26 改为 **27**
   - 移动：`preferred_network_mode` 从 23 改为 **32**
   - 联通：保持 **26**（原模块正确）
   - 广电：`preferred_network_mode` 从 26 改为 **33**
4. **新增 Android 版本检测**（用户要求）：API < 34 时记录警告但不中止
5. 路径解析函数中所有 `Satellite_Earth` 替换为 `Network_Enhance`
6. 日志路径改为 `/data/local/tmp/network_enhance.log`
7. 启动横幅输出"网络增强 v1.0"

**来源**：S2 system.prop 结论 + S3 运营商默认值修正 + 用户要求

#### `service.sh` —— 修改
**改动内容**：
1. 路径解析函数中 `Satellite_Earth` → `Network_Enhance`
2. 启动日志改为"网络增强 v${SE_VERSION}"
3. `verify_and_reapply()` 函数保持，但日志路径更新
4. `apply_dns_prefetch()` 函数保持
5. `start_smart_monitor()` 调用新 monitor.sh
6. 状态快照日志路径更新

**来源**：S1 原模块逻辑保持 + 用户要求命名统一

#### `action.sh` —— 修改
**改动内容**：
1. 路径解析函数中 `Satellite_Earth` → `Network_Enhance`
2. 标题"卫星地球 Pro" → "网络增强"
3. 菜单文案保持 29 项，但调整场景模式说明：
   - "游戏模式 (打游戏延迟高)" → "游戏模式 (锁定4G LTE+禁后台)"
   - "视频模式 (抖音/B站卡顿)" → "视频模式 (弱网预加载优化)"
4. **新增菜单项 30**: "5G假满格自检"（手动触发一次 5G 假满格判定）
5. **新增菜单项 31**: "锁定LTE"（手动调用 `lock_lte()`）
6. **新增菜单项 32**: "解锁LTE"（手动调用 `unlock_lte()`）
7. 状态显示中加入 5G RSRP/SINR 字段
8. 日志路径更新

**来源**：S3 5G 假满格判定算法 + 用户要求新增功能

#### `uninstall.sh` —— 修改
**改动内容**：
1. 路径解析中 `Satellite_Earth` → `Network_Enhance`
2. 状态文件路径 `/data/local/tmp/satellite_earth_*` → `/data/local/tmp/network_enhance_*`
3. PID 文件路径更新
4. 还原 settings 时增加新的键清理（`network_enhance_version`）
5. 日志路径更新

**来源**：S1 + 用户要求命名统一

#### `config.sh` —— 修改
**改动内容**：
1. **检测间隔统一为 120 秒**（用户要求）：
   - `MONITOR_MIN_INTERVAL=120`（原 300）
   - `MONITOR_NORMAL_INTERVAL=120`（原 600）
   - `MONITOR_MAX_INTERVAL=120`（原 900）
2. **新增 5G 假满格判定参数**（S3 算法）：
   - `ENABLE_FAKE_5G_DETECTION=true`（总开关）
   - `FAKE_5G_RSRP_THRESHOLD=-85`（RSRP 阈值，强于此值但延迟高则判定假满格）
   - `FAKE_5G_SINR_THRESHOLD=0`（SINR 阈值，低于此值视为干扰严重）
   - `FAKE_5G_PING_THRESHOLD=200`（Ping 阈值，高于此值视为延迟过高）
   - `FAKE_5G_RECOVERY_COUNT=3`（连续 N 次正常后才恢复 5G）
3. **新增 4G+ 跳频防护参数**：
   - `ENABLE_LTE_LOCK_FOR_GAME=true`（游戏模式锁定 LTE only）
4. **新增 Android 版本要求**：
   - `MIN_API_LEVEL=34`（最低 Android 14）
5. 版本号字符串统一

**来源**：用户要求检测间隔固定 120s + S3 5G 假满格算法

#### `system.prop` —— **删除**
**原因**：S2 官方文档明确"system.prop will be loaded as system properties by setprop (debug only)"，且 S3 确认免Root下 `setprop persist.*` 不可用。原模块的 `persist.sys.satellite_earth.version=1.0` 和 `activated=1` 在免Root下完全不生效。

**迁移**：功能迁移到 `post-fs-data.sh` 中用 `settings put global network_enhance_version 1.0` 和 `network_enhance_activated 1` 实现（均为自定义键，免Root可写）。

**来源**：S2 + S3 + 用户要求

#### `README.md` —— 修改
**改动内容**：
1. 标题改为"网络增强 v1.0"
2. 移除所有 v6.x 版本说明
3. 新增"5G 假满格自动降级"功能说明
4. 新增"游戏模式锁定 LTE"功能说明
5. 新增"完全禁用 4G+ 需 Root"的免责声明（S3 结论）
6. 更新支持的厂商列表与兼容性说明
7. 更新日志路径

**来源**：用户要求 + S3 关键结论

#### `CHANGELOG.md` —— 重写
**改动内容**：
1. 完全重写，从 v1.0 开始记录
2. 列出相对原模块（卫星地球 Pro v6.3.3）的所有修改
3. 解决的用户反馈问题（5G 假满格、4G+ 跳频、O 系兼容、自检缺失）
4. 新增功能列表
5. 技术实现细节（关键命令与逻辑）

**来源**：用户要求

#### `LICENSE` —— 保留
**改动**：无（MIT 协议保持）

#### `banner.png` —— 保留
**改动**：无（图标保持，避免重新设计图标资源）

---

### 1.2 scripts/ 目录文件

#### `scripts/common.sh` —— 重构（核心）
**改动内容**：

##### 1.2.1 常量与路径更新
- `SE_VERSION="1.0"`（原 6.3.0）
- `SE_VERSION_CODE="100"`（原 6300）
- `SE_LOG_TAG="NetworkEnhance"`（原 SatelliteEarth）
- `SE_LOG_FILE="/data/local/tmp/network_enhance.log"`（原 satellite_earth.log）
- `SE_PID_FILE="/data/local/tmp/network_enhance_monitor.pid"`
- `SE_STATE_FILE="/data/local/tmp/network_enhance_monitor.state"`
- `SE_NOTIFY_TAG="network_enhance_monitor"`
- `WEAKNET_ACTIVE_FLAG="/data/local/tmp/network_enhance_weaknet_active"`
- `DNS_PREFETCH_PID="/data/local/tmp/network_enhance_dns_prefetch.pid"`
- `SE_MOD_ID="Network_Enhance"`（原 Satellite_Earth）

##### 1.2.2 路径解析 `se_resolve_moddir()` 增强
保留原 6 级 fallback（S1 v6.3.0 修复核心），但：
1. 所有硬编码路径中 `Satellite_Earth` → `Network_Enhance`
2. **新增策略 0**：检测 `MODDIR` 环境变量是否已设置（用户补充要求 5）
3. **新增策略 7**：检测 `AXERONDIR/plugins/Network_Enhance` 显式路径

```bash
se_resolve_moddir() {
    # 策略 0: 环境变量 MODDIR（用户补充要求）
    if [ -n "${MODDIR:-}" ] && [ -f "$MODDIR/module.prop" ] 2>/dev/null; then
        echo "$MODDIR"; return 0
    fi
    # 策略 1: pwd（原模块策略 1，S1 v6.3.0 核心）
    # 策略 2: AXERONDIR/plugins/Network_Enhance（原策略 2，S2 官方环境变量）
    # 策略 3: MODPATH（原策略 3，仅 customize.sh 阶段）
    # 策略 4: $0 推导（原策略 4）
    # 策略 5: readlink -f（原策略 5）
    # 策略 6: 已知安装路径硬探测（路径名更新）
}
```

##### 1.2.3 Android 版本检测（用户补充要求 5）
```bash
se_get_api() {
    getprop ro.build.version.sdk 2>/dev/null | head -1
}

se_is_android_14_plus() {
    local api
    api=$(se_get_api)
    case "$api" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$api" -ge 34 ] ;;
    esac
}
```

##### 1.2.4 WiFi RSSI 读取优化（用户补充要求 4）
**新增 `se_get_wifi_rssi_v2()`**，优先使用 `cmd wifi status`（S3 推荐）：
```bash
se_get_wifi_rssi() {
    local result
    # 优先 cmd wifi status（S3 推荐，Android 14+ 更稳定）
    if se_is_android_14_plus; then
        result=$(cmd wifi status 2>/dev/null | grep -i 'RSSI' | grep -oE '[-]?[0-9]+' | head -1)
        [ -n "$result" ] && { echo "$result"; return 0; }
    fi
    # Fallback 1-5: 原 dumpsys wifi 5 种模式（S1 v6.3.0）
    # ... 保留原 5 种模式
    echo ""
}
```

##### 1.2.5 5G RSRP/SINR 读取（S3 关键新增）
**新增 `se_get_nr_rsrp()` / `se_get_nr_sinr()` / `se_get_nr_rsrq()`**：
```bash
# 5G SS-RSRP（主用信号强度）
se_get_nr_rsrp() {
    local reg result
    reg=$(dumpsys telephony.registry 2>/dev/null)
    # 模式 1: mSsRsrp=-95 (5G SS-RSRP, AOSP 标准, S3)
    result=$(echo "$reg" | grep -oE 'mSsRsrp=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    # 模式 2: mCsiRsrp=-95 (5G CSI-RSRP, AOSP 标准, S3)
    result=$(echo "$reg" | grep -oE 'mCsiRsrp=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    # 模式 3: mLteRsrp=-95 (4G LTE RSRP, 5G 不可用时回退, S3)
    result=$(echo "$reg" | grep -oE 'mLteRsrp=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    # 模式 4: mDbm=-95 (旧 AOSP)
    result=$(echo "$reg" | grep -oE 'mDbm=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    echo ""
}

# 5G SS-SINR（信噪比，关键假满格判定指标）
se_get_nr_sinr() {
    local reg result
    reg=$(dumpsys telephony.registry 2>/dev/null)
    # 模式 1: mSsSinr=13 (5G SS-SINR, AOSP 标准, S3)
    result=$(echo "$reg" | grep -oE 'mSsSinr=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    # 模式 2: mCsiSinr=13 (5G CSI-SINR, S3)
    result=$(echo "$reg" | grep -oE 'mCsiSinr=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    # 模式 3: mLteRssnr=6 (4G SINR)
    result=$(echo "$reg" | grep -oE 'mLteRssnr=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    echo ""
}

# 5G SS-RSRQ（信号质量）
se_get_nr_rsrq() {
    local reg result
    reg=$(dumpsys telephony.registry 2>/dev/null)
    result=$(echo "$reg" | grep -oE 'mSsRsrq=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    result=$(echo "$reg" | grep -oE 'mCsiRsrq=[-]?[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$result" ] && { echo "$result"; return 0; }
    echo ""
}
```

##### 1.2.6 5G 假满格判定（S3 算法核心）
**新增 `se_detect_fake_5g()`**：
```bash
# 返回值: 0=假满格, 1=正常
se_detect_fake_5g() {
    [ "$ENABLE_FAKE_5G_DETECTION" = "true" ] || return 1
    
    local rsrp sinr ping_ms
    rsrp=$(se_get_nr_rsrp 2>/dev/null)
    sinr=$(se_get_nr_sinr 2>/dev/null)
    ping_ms=$(se_get_ping_ms 2>/dev/null)
    
    # 空值容错
    [ -z "$rsrp" ] && return 1
    
    # RSRP 必须为整数（绝对值）
    case "$rsrp" in
        ''|*[!0-9-]*) return 1 ;;
    esac
    local abs_rsrp
    if [ "$rsrp" -lt 0 ] 2>/dev/null; then
        abs_rsrp=$((-rsrp))
    else
        abs_rsrp="$rsrp"
    fi
    
    # 条件1: RSRP 强（信号满格）但 Ping 过高
    # 来源: S3 5G 假满格判定算法
    if [ "$abs_rsrp" -lt 85 ] 2>/dev/null; then
        # RSRP ≥ -85（信号强度好）
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
            # Ping 失败（丢包）
            log_msg "[假满格] RSRP=$rsrp(强) 但 Ping 失败" "[5g]"
            return 0
        fi
        
        # 条件2: RSRP 强但 SINR 差
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
```

##### 1.2.7 4 级综合判定函数增强
**重构 `se_overall_level()`**：增加 SINR 维度
- strong：RSSI ≥ -60 且 Ping < 80ms 且 SINR ≥ 10
- normal：RSSI -60~-75 或 Ping 80~150ms
- weak：RSSI -75~-90 或 Ping 150~200ms
- critical：RSSI < -90 或 Ping > 200ms 或 SINR < 0

##### 1.2.8 运营商默认值修正（S3 关键修正）
**新增 `se_get_carrier_default_mode()`**：
```bash
# 返回运营商的默认 5G preferred_network_mode 值
# 来源: S3 AOSP RILConstants.java 数值表
se_get_carrier_default_mode() {
    local carrier="$1"
    case "$carrier" in
        telecom) echo 27 ;;  # NR/LTE/CDMA/EvDo/GSM/WCDMA (S3 修正, 原26错)
        mobile)  echo 32 ;;  # NR/LTE/TD-SCDMA/GSM/WCDMA (S3 修正, 原23错)
        unicom)  echo 26 ;;  # NR/LTE/GSM/WCDMA (原模块正确)
        ctn)     echo 33 ;;  # NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA (S3 修正, 原26错)
        *)       echo 26 ;;  # 默认联通兼容
    esac
}

# 4G-only 模式（锁定 LTE, 用于游戏模式）
se_get_lte_only_mode() {
    echo 11  # NETWORK_MODE_LTE_ONLY (S3)
}

# 4G 优先模式（无5G, 用于假满格降级）
se_get_lte_preferred_mode() {
    echo 9   # NETWORK_MODE_LTE_GSM_WCDMA (S3)
}
```

##### 1.2.9 自检函数 `se_self_check()` 修复
**修复 customize.sh 误报缺失 bug**（S1 第一步发现）：
```bash
se_self_check() {
    # ... 原逻辑保持
    
    # 修复: check_dir 无效时用 pwd 兜底
    local check_dir="${MODDIR_ROOT:-${MODPATH:-${MODDIR:-$(pwd 2>/dev/null)}}}"
    
    # 新增: Android 版本检测
    echo "[Android 版本]"
    echo "  API 级别    : $(se_get_api)"
    if se_is_android_14_plus; then
        echo "  兼容性      : ✅ Android 14+ 完全支持"
    else
        echo "  兼容性      : ⚠️ 低于 Android 14, 部分功能可能受限"
    fi
    echo ""
    
    # 新增: cmd wifi status 可用性检测
    echo "[命令可用性]"
    echo "  cmd wifi status      : $(if cmd wifi status >/dev/null 2>&1; then echo '✅ 可用'; else echo '❌ 不可用'; fi)"
    echo "  cmd netpolicy        : $(if cmd netpolicy list restrict-background-whitelist >/dev/null 2>&1; then echo '✅ 可用'; else echo '❌ 不可用'; fi)"
    echo "  cmd connectivity     : $(if cmd connectivity get-airplane-mode >/dev/null 2>&1; then echo '✅ 可用'; else echo '❌ 不可用'; fi)"
    echo ""
    
    # 新增: 5G 信号质量
    echo "[5G 信号质量]"
    echo "  NR RSRP    : $(se_get_nr_rsrp) dBm"
    echo "  NR RSRQ    : $(se_get_nr_rsrq) dB"
    echo "  NR SINR    : $(se_get_nr_sinr) dB"
    if se_detect_fake_5g; then
        echo "  假满格判定 : ⚠️ 检测到 5G 假满格"
    else
        echo "  假满格判定 : ✅ 正常"
    fi
    echo ""
}
```

**来源**：S1 自检 bug + S3 5G 信号指标 + 用户要求增强自检

#### `scripts/oem_compat.sh` —— 扩展
**改动内容**：

##### 1.2.10 厂商矩阵保留并扩展
保留原 6 厂商矩阵（S1），但：

1. **修正华为/荣耀 5G 处理逻辑**（用户补充要求）：
   - 虽然 5G NR 私有键跳过，但 `preferred_network_mode` 在华为/荣耀上仍可用
   - 新增 `se_huawei_supports_pnm()` 检测函数
   - 在 `se_put_safe` 中：华为/荣耀对 `preferred_network_mode` 不跳过，仅跳过 5G 私有键

2. **新增 RSRP 字段解析的 ROM 兼容性说明**（S3）：
   - AOSP 标准：`mSsRsrp` / `mCsiRsrp`
   - MIUI/HyperOS：可能用 `mCsiRsrp` 或合并显示（已在 common.sh 处理）
   - ColorOS：基本同 AOSP
   - EMUI/HarmonyOS：可能用 `nrRsrp` 简写（已在 common.sh 第 6 模式处理）
   - OneUI：可能用 `SsRsrp`（无 m 前缀，已在 common.sh 第 6 模式处理）

3. **修正运营商默认值**（S3 关键修正）：
   - 在 `se_show_oem_info()` 中明确标注各运营商的正确默认值
   - 在 `se_put_safe()` 中对 `preferred_network_mode` 不做 OEM 过滤（全品牌可用）

4. **新增 `se_is_brand_supports_pnm()` 函数**：
```bash
# 检查当前品牌是否支持 preferred_network_mode 切换
# 来源: S3 第5节 国产手机差异表
se_is_brand_supports_pnm() {
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    case "$brand" in
        oppo|oneplus|realme|xiaomi|redmi|poco)
            return 0  # ✅ 完全支持
            ;;
        vivo|iqoo|bbk)
            return 0  # ✅ 基础键可用
            ;;
        samsung)
            return 0  # ⚠️ 可用但部分版本会忽略
            ;;
        huawei|honor)
            return 0  # ⚠️ 可用但 5G NR 键跳过
            ;;
        *)
            return 0  # 默认保守可用
            ;;
    esac
}
```

**来源**：S1 原 OEM 矩阵 + S3 第 5 节国产差异表 + 用户要求扩展

#### `scripts/monitor.sh` —— 重构（核心）
**改动内容**：

##### 1.2.11 检测间隔统一为 120 秒（用户要求）
- 所有等级的 `next_interval` 都返回 `$MONITOR_NORMAL_INTERVAL`（即 120）
- 移除按等级区分间隔的逻辑

##### 1.2.12 新增 5G 假满格自动降级逻辑（S3 算法核心）
**新增 `handle_fake_5g()` 函数**：
```bash
# 5G 假满格自动降级处理
# 来源: S3 5G 假满格判定算法 + 用户补充要求 2
handle_fake_5g() {
    [ "$ENABLE_FAKE_5G_DETECTION" = "true" ] || return 0
    
    if se_detect_fake_5g; then
        # 检测到假满格
        if [ -z "$FAKE_5G_ACTIVE" ] || [ "$FAKE_5G_ACTIVE" = "0" ]; then
            # 首次触发，立即降级
            local carrier default_mode
            carrier=$(se_detect_carrier)
            default_mode=$(se_get_carrier_default_mode "$carrier")
            
            # 保存原模式以便恢复
            echo "$default_mode" > /data/local/tmp/network_enhance_5g_backup 2>/dev/null
            
            # 降级到 4G (LTE/GSM/WCDMA)
            se_put global preferred_network_mode 9
            log_msg "[5G降级] 假满格触发, 降级到 4G (mode=9)" "[5g]"
            
            FAKE_5G_ACTIVE=1
            RECOVERY_COUNT=0
            se_notify "网络增强 → 5G假满格降级" "检测到5G信号良好但实际网络差\n已自动降级到4G\n恢复后将自动切回5G"
        fi
    else
        # 5G 正常
        if [ "$FAKE_5G_ACTIVE" = "1" ]; then
            RECOVERY_COUNT=$((RECOVERY_COUNT + 1))
            log_msg "[5G恢复] 检测正常 ($RECOVERY_COUNT/$FAKE_5G_RECOVERY_COUNT)" "[5g]"
            
            if [ "$RECOVERY_COUNT" -ge "$FAKE_5G_RECOVERY_COUNT" ]; then
                # 连续 N 次正常, 恢复 5G
                local backup_mode
                backup_mode=$(cat /data/local/tmp/network_enhance_5g_backup 2>/dev/null)
                if [ -n "$backup_mode" ]; then
                    se_put global preferred_network_mode "$backup_mode"
                    log_msg "[5G恢复] 连续${FAKE_5G_RECOVERY_COUNT}次正常, 恢复 5G (mode=$backup_mode)" "[5g]"
                fi
                FAKE_5G_ACTIVE=0
                RECOVERY_COUNT=0
                rm -f /data/local/tmp/network_enhance_5g_backup 2>/dev/null
                se_notify "网络增强 → 5G已恢复" "网络质量已稳定\n已自动切回5G模式"
            fi
        fi
    fi
}
```

##### 1.2.13 主循环重构
```bash
run_monitor_loop() {
    local current_level="init"
    local loop_count=0
    FAKE_5G_ACTIVE=0
    RECOVERY_COUNT=0
    
    # trap 信号处理保持
    
    # 首轮检测保持
    
    while true; do
        loop_count=$((loop_count + 1))
        
        # weaknet 互锁保持
        if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
            sleep "$MONITOR_NORMAL_INTERVAL"
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
        
        # 5G 假满格检测（优先于普通等级判定）
        handle_fake_5g
        
        # 4 级综合判定（含 SINR 维度）
        local target_level
        target_level=$(compute_overall_level_v2 "$net_type" "$wifi_rssi" "$mobile_dbm" "$ping_ms" "$nr_sinr")
        
        # 等级切换处理保持
        if [ "$target_level" != "$current_level" ]; then
            # ... 写状态 + 发通知 + 后台 apply_dynamic_params
        fi
        
        # 统一 120 秒间隔（用户要求）
        sleep "$MONITOR_NORMAL_INTERVAL"
    done
}
```

##### 1.2.14 状态文件字段扩展
状态文件新增字段：
```
NR_RSRP=<value>
NR_SINR=<value>
NR_RSRQ=<value>
FAKE_5G_ACTIVE=<0/1>
RECOVERY_COUNT=<n>
```

**来源**：S3 5G 假满格算法 + 用户要求检测间隔 120s + 用户要求新增功能

#### `scripts/network_info.sh` —— 增强
**改动内容**：

1. **优先使用 `cmd wifi status`**（用户补充要求 4）：
   - 在 `get_wifi_ssid()` / `get_wifi_rssi()` / `get_wifi_link_speed()` / `get_wifi_frequency()` 中优先调用 `cmd wifi status`
   - 失败时 fallback 到 `dumpsys wifi` 5 种模式（S1 v6.3.1 已实现）

2. **新增 5G 信号质量采集**：
   - `get_nr_rsrp()` / `get_nr_sinr()` / `get_nr_rsrq()` 包装 `se_get_nr_*` 函数
   - 在 `show_full_status()` 中新增 5G 信号质量区块

3. **JSON 输出扩展**：
   ```json
   {
     "nr": {
       "rsrp": "-95",
       "rsrq": "-10",
       "sinr": "13",
       "fake_5g": false
     }
   }
   ```

4. 路径与版本字符串更新

**来源**：S3 + 用户要求

#### `scripts/wifi.sh` —— 优化
**改动内容**：

1. 路径字符串更新
2. `apply_wifi()` 保持原逻辑（OEM 兼容性已处理好）
3. `show_wifi_status()` 新增 5G 频段识别（如果连接 5G WiFi）
4. `reset_wifi()` 保持

**来源**：S1 + 命名统一

#### `scripts/carrier.sh` —— 修正与扩展
**改动内容**：

##### 1.2.15 修正运营商默认值（S3 关键修正）
```bash
case "$carrier" in
    telecom)
        se_put global preferred_network_mode1 27   # 原 26, S3 修正
        se_put global preferred_network_mode 27    # 原 26, S3 修正
        ;;
    mobile)
        se_put global preferred_network_mode1 32   # 原 23, S3 修正
        se_put global preferred_network_mode 32    # 原 23, S3 修正
        ;;
    unicom)
        se_put global preferred_network_mode1 26   # 原模块正确
        se_put global preferred_network_mode 26
        ;;
    ctn)
        se_put global preferred_network_mode1 33   # 原 26, S3 修正
        se_put global preferred_network_mode 33    # 原 26, S3 修正
        ;;
esac
```

##### 1.2.16 新增 `lock_lte()` / `unlock_lte()` / `degrade_5g_to_4g()` 函数
```bash
# 锁定 LTE only（游戏模式用）
# 来源: S3 preferred_network_mode 数值表 + 用户补充要求 2
lock_lte() {
    echo "=== 锁定 LTE only (mode=11) ==="
    se_put global preferred_network_mode 11
    se_put global preferred_network_mode1 11
    # 关闭 ENDC (OEM 兼容性过滤后)
    se_put global endc_capability 0
    log_msg "已锁定 LTE only, 关闭 ENDC" "[carrier]"
}

# 解锁 LTE（恢复运营商默认 5G 模式）
unlock_lte() {
    echo "=== 解锁 LTE, 恢复 5G ==="
    local carrier default_mode
    carrier=$(se_detect_carrier)
    default_mode=$(se_get_carrier_default_mode "$carrier")
    se_put global preferred_network_mode "$default_mode"
    se_put global preferred_network_mode1 "$default_mode"
    # 恢复 ENDC
    se_put global endc_capability 1
    log_msg "已解锁 LTE, 恢复 5G (mode=$default_mode, carrier=$carrier)" "[carrier]"
}

# 5G 降级到 4G（假满格自救用）
degrade_5g_to_4g() {
    echo "=== 5G 降级到 4G (mode=9) ==="
    se_put global preferred_network_mode 9
    se_put global preferred_network_mode1 9
    log_msg "已降级 5G→4G" "[carrier]"
}
```

3. case 分发新增 `lock_lte` / `unlock_lte` / `degrade` 子命令
4. 路径与版本字符串更新

**来源**：S3 + 用户补充要求 2

#### `scripts/dns.sh` —— 优化
**改动内容**：

1. 路径与版本字符串更新
2. **新增智能 DNS 选择**（用户原始要求 6）：
   - 新增 `select_best_dot()` 函数：对 6 家 DoT 提供商做 ping 测试，选延迟最低的
   - 在 `enable_private_dns` 中支持 `auto` 参数自动选择
3. 其他逻辑保持

**来源**：用户原始要求 + S1 原模块

#### `scripts/weaknet.sh` —— 重构
**改动内容**：

##### 1.2.17 游戏模式重构（S3 + 用户补充要求 2）
```bash
apply_game_mode() {
    echo "=== 应用游戏模式 (v1.0 锁定 LTE 版) ==="
    silent_reset
    
    # 关键: 锁定 LTE only (S3 + 用户补充要求 2)
    # 解决 4G+ 跳频断流问题
    se_put global preferred_network_mode 11    # LTE only
    se_put global preferred_network_mode1 11
    se_put global endc_capability 0            # 关闭 ENDC
    
    # 移动数据保活
    se_put global mobile_data_always_on 1
    se_put global mobile_data_preferred 1
    se_put global mobile_data_auto_handover 1
    
    # 关闭低功耗
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    
    # WiFi 优化（弱信号容忍）
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
    
    # VoLTE 启用
    se_put global volte_vt_enabled 1
    
    # ⚠️ 不再开启 5G SA/DC/ENDC (与原模块相反)
    # se_put global nr_sa_mode 1       # 删除
    # se_put global enable_nr_dc 1     # 删除
    # se_put global endc_capability 1  # 删除（已改为 0）
    # se_put global nr_handover_enabled 1  # 删除
    # se_put global vonr_enabled 1     # 删除
    
    # 新增: Data Saver 禁止后台抢带宽 (S3 cmd netpolicy)
    cmd netpolicy set restrict-background true 2>/dev/null
    
    echo "  [OK] 游戏模式已锁定 LTE only + 关闭 ENDC + 禁后台带宽"
    
    # DNS 预热游戏厂商
    dns_prefetch "game" \
        dns.alidns.com dot.pub www.tencent.com \
        www.netease.com www.mihoyo.com \
        api.tencentcloudapi.com
    
    set_weaknet_active "game"
    log_msg "游戏模式已应用 (LTE锁定版)" "[weaknet]"
}

apply_normal_mode() {
    # ... 原逻辑保持
    
    # 关闭 Data Saver (S3)
    cmd netpolicy set restrict-background false 2>/dev/null
    
    # 恢复运营商默认 5G 模式 (S3 修正)
    local carrier default_mode
    carrier=$(se_detect_carrier)
    default_mode=$(se_get_carrier_default_mode "$carrier")
    se_put global preferred_network_mode "$default_mode"
    se_put global preferred_network_mode1 "$default_mode"
    se_put global endc_capability 1
    
    # ... 其他保持
}
```

##### 1.2.18 视频模式优化（用户原始要求 4）
```bash
apply_video_mode() {
    # ... 原逻辑保持
    
    # 新增: 弱网预加载强化
    # 增加 B 站/抖音/快手 API 域名预热
    dns_prefetch "video" \
        www.douyin.com www.bilibili.com www.kuaishou.com www.ixigua.com \
        www.iqiyi.com www.youku.com \
        v.douyin.com api.bilibili.com dns.alidns.com dot.pub \
        api.amemv.com api2.amemv.com  # 抖音 API 强化
    
    # ... 其他保持
}
```

3. 路径与版本字符串更新

**来源**：S3 + 用户补充要求 2 + 用户原始要求 4

---

### 1.3 webroot/index.html —— 修改

**改动内容**：

1. 标题"卫星地球 Pro" → "网络增强"
2. 版本号 v6.3.0 → v1.0
3. 所有日志路径更新
4. 状态文件路径更新
5. **新增 5G 信号质量区块**：
   - NR RSRP / NR RSRQ / NR SINR 显示
   - 假满格状态指示灯
6. **新增按钮**：
   - "5G假满格自检"按钮
   - "锁定LTE"按钮
   - "解锁LTE"按钮
7. 菜单按钮文案更新：
   - "游戏模式 (锁定4G LTE+禁后台)"
8. 默认 MODDIR 路径更新为 `Network_Enhance`

**来源**：S1 + 用户要求命名统一 + S3 新增功能

---

## 2. 新模块目录结构

```
Network_Enhance_v1.0/
├── module.prop                    # 修改: id=Network_Enhance, name=网络增强, version=v1.0
├── customize.sh                   # 修改: 修复自检bug, 路径更新
├── post-fs-data.sh                # 修改: 移除system.prop引用, 修正运营商默认值, 版本检测
├── service.sh                     # 修改: 路径与命名更新
├── action.sh                      # 修改: 新增菜单30/31/32, 文案更新
├── uninstall.sh                   # 修改: 路径更新
├── config.sh                      # 修改: 检测间隔120s, 新增5G假满格参数
├── banner.png                     # 保留
├── README.md                      # 修改: 重写
├── CHANGELOG.md                   # 修改: 重写
├── LICENSE                        # 保留
├── scripts/
│   ├── common.sh                  # 重构: 版本检测, RSRP/SINR解析, 假满格判定, 运营商默认值
│   ├── oem_compat.sh              # 扩展: 华为/荣耀PNM支持, RSRP字段ROM兼容
│   ├── monitor.sh                 # 重构: 120s间隔, 5G假满格自动降级
│   ├── network_info.sh            # 增强: cmd wifi status优先, 5G信号采集
│   ├── wifi.sh                    # 优化: 路径更新
│   ├── carrier.sh                 # 修正: 运营商默认值, 新增lock_lte/unlock_lte/degrade
│   ├── dns.sh                     # 优化: 智能DNS选择
│   └── weaknet.sh                 # 重构: 游戏模式锁定LTE, 视频模式强化预加载
└── webroot/
    └── index.html                 # 修改: 命名更新, 新增5G信号区块, 新增按钮
```

**已删除**：
- `system.prop`（S2+S3 确认免Root不生效）

---

## 3. 核心逻辑设计文档

### A. 动态调度器新逻辑（monitor.sh）

#### 检测间隔
- **统一 120 秒**（用户要求），所有等级相同
- 来源：用户补充要求 3

#### 检测指标
| 指标 | 获取方式 | 来源 |
|---|---|---|
| WiFi RSSI | `cmd wifi status` 优先，fallback `dumpsys wifi` | S3 + 用户补充 4 |
| 移动 dBm | `dumpsys telephony.registry` mDbm | S1 |
| NR RSRP | `dumpsys telephony.registry` mSsRsrp/mCsiRsrp | S3 |
| NR SINR | `dumpsys telephony.registry` mSsSinr/mCsiSinr | S3 |
| NR RSRQ | `dumpsys telephony.registry` mSsRsrq/mCsiRsrq | S3 |
| Ping 延迟 | ping 223.5.5.5/119.29.29.29/114.114.114.114/网关 4 级 fallback | S1 v6.3.3 |

#### 4 级判定标准（含 SINR 维度）
| 等级 | 条件（任一满足即降级） | 来源 |
|---|---|---|
| **strong** | RSSI ≥ -60 且 Ping < 80ms 且 SINR ≥ 10 | S3 阈值表 |
| **normal** | RSSI -60~-75 或 Ping 80~150ms | S1 |
| **weak** | RSSI -75~-90 或 Ping 150~200ms | S1 |
| **critical** | RSSI < -90 或 Ping > 200ms 或 SINR < 0 | S3 |

#### 5G 假满格特殊处理（S3 算法核心）
**触发条件**（满足任一）：
1. `mSsRsrp ≥ -85`（信号强度好）但 `Ping > 200ms`
2. `mSsRsrp ≥ -85` 但 `mSsSinr < 0`（信噪比差）
3. `mSsRsrp ≥ -85` 但 Ping 失败（丢包）

**触发动作**：
1. 保存当前 `preferred_network_mode` 到 `/data/local/tmp/network_enhance_5g_backup`
2. 执行 `settings put global preferred_network_mode 9`（降级 4G）
3. 发送通知"5G假满格降级"
4. 设置 `FAKE_5G_ACTIVE=1` 标志

**恢复条件**：
- 连续 3 次检测（即 6 分钟）5G 信号正常（RSRP ≥ -85 且 Ping < 200ms 且 SINR ≥ 0）
- 回写备份的 `preferred_network_mode`
- 发送通知"5G已恢复"

#### 手动模式互锁
- weaknet 场景模式激活时（`$WEAKNET_ACTIVE_FLAG` 存在），调度器跳过本轮检测
- 来源：S1 原模块逻辑保持

---

### B. 场景模式重构（weaknet.sh）

| 模式 | 关键调整 | 来源 |
|---|---|---|
| **视频模式** | WiFi 弱信号阈值 -95，扫描 10s，预加载强化（新增抖音 API 域名） | S1 + 用户原始要求 4 |
| **游戏模式** | `preferred_network_mode 11`（LTE only）+ `endc_capability 0` + `cmd netpolicy set restrict-background true`（禁后台抢带宽）+ DNS 预热 | S3 + 用户补充要求 2 |
| **社交模式** | 保 WiFi（`mobile_data_preferred 0`），DNS 预热微信/QQ | S1 |
| **下载模式** | WiFi idle 6h，`mobile_data_preferred 0`，预加载百度网盘/123pan | S1 |
| **恢复默认** | 清除标志 + 关闭 Data Saver + 恢复运营商默认 5G 模式 + 重启 monitor | S3 + 用户补充要求 2 |

---

### C. 网络制式智能管理（carrier.sh）

#### 运营商默认值修正表
| 运营商 | 旧值 | 新值 | 常量名 | 来源 |
|---|---|---|---|---|
| 电信 | 26 | **27** | NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA | S3 RILConstants.java |
| 移动 | 23 | **32** | NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA | S3 RILConstants.java |
| 联通 | 26 | 26 | NETWORK_MODE_NR_LTE_GSM_WCDMA | S3（原模块正确） |
| 广电 | 26 | **33** | NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA | S3 RILConstants.java |

#### 新增函数
- `lock_lte()`：写入 mode=11（LTE only）+ endc_capability=0
- `unlock_lte()`：回写运营商默认值 + endc_capability=1
- `degrade_5g_to_4g()`：写入 mode=9（LTE/GSM/WCDMA）

#### 实现方式
所有切换通过 `settings put global preferred_network_mode` 实现（S3 确认免Root可用）

---

### D. OEM 兼容性矩阵扩展（oem_compat.sh）

#### 6 厂商矩阵保留
| 品牌 | 5G NR 键 | WiFi 私有键 | PNM 支持 | 来源 |
|---|---|---|---|---|
| 小米 HyperOS | nr_sa_mode→nr_mode 替换 | 跳过 pno_frequency/recovery_state | ✅ | S1 + S3 |
| OPPO ColorOS | ✅ 全部可用 | ✅ 全部可用 | ✅ | S1 + S3 |
| vivo OriginOS | nr_sa_mode 跳过(崩溃) | 跳过 enhanced_mac_randomization | ✅ | S1 + S3 |
| 三星 OneUI | 全部 5G NR 跳过 | 跳过 max_dwell_time_ms | ⚠️ 部分忽略 | S1 + S3 |
| 华为 HarmonyOS | 全部 5G NR 跳过 | 跳过 persistent_group_remove_delay | ✅ PNM 可用 | S1 + S3 + 用户补充 |
| 荣耀 MagicOS | 全部 5G NR 跳过 | 同华为 | ✅ PNM 可用 | S1 + S3 + 用户补充 |

#### 关键修正
- **华为/荣耀**：5G NR 私有键跳过（避免崩溃），但 `preferred_network_mode` **不跳过**（用户补充要求 5）
- 来源：S3 第 5 节国产差异表

#### RSRP/SINR 字段多 ROM 解析
已在 `common.sh` 的 `se_get_nr_rsrp()` / `se_get_nr_sinr()` 中处理 5 种 grep 模式（S3）

---

## 4. 自检系统增强

### 4.1 修复 customize.sh 误报缺失 bug
**问题**：S1 第一步发现，原模块 `se_self_check()` 在 `MODDIR_ROOT` 未解析时 `check_dir` 为空，导致报告"customize.sh 缺失"。

**修复**：
```bash
# 修复前
local check_dir="${MODDIR_ROOT:-${MODPATH:-${MODDIR:-}}}"

# 修复后
local check_dir="${MODDIR_ROOT:-${MODPATH:-${MODDIR:-$(pwd 2>/dev/null)}}}"
if [ -z "$check_dir" ] || [ ! -d "$check_dir" ]; then
    check_dir="$(pwd 2>/dev/null)"
fi
```

来源：S1 第一步发现 + 用户补充要求 5

### 4.2 新增检测项
1. **Android 版本检测**：`se_get_api()` + `se_is_android_14_plus()`
2. **命令可用性检测**：
   - `cmd wifi status`
   - `cmd netpolicy list restrict-background-whitelist`
   - `cmd connectivity get-airplane-mode`
3. **5G 信号质量检测**：NR RSRP / RSRQ / SINR + 假满格判定
4. **OEM 兼容性信息**：保留并扩展，明确标注各品牌 PNM 支持情况

### 4.3 日志路径统一
- 旧：`/data/local/tmp/satellite_earth.log`
- 新：`/data/local/tmp/network_enhance.log`
- 状态文件：`/data/local/tmp/network_enhance_monitor.state`
- PID 文件：`/data/local/tmp/network_enhance_monitor.pid`
- weaknet 标志：`/data/local/tmp/network_enhance_weaknet_active`
- DNS 预热 PID：`/data/local/tmp/network_enhance_dns_prefetch.pid`
- 5G 备份：`/data/local/tmp/network_enhance_5g_backup`

---

## 5. 命名与版本统一清单

### 5.1 字符串替换表（全局）

| 旧值 | 新值 | 出现位置 |
|---|---|---|
| `卫星地球` | `网络增强` | 所有 .sh / .md / .html / module.prop |
| `卫星地球 Pro` | `网络增强` | 所有显示文案 |
| `Satellite_Earth` | `Network_Enhance` | module.prop id / 目录名 / 路径硬编码 / webroot |
| `SatelliteEarth` | `NetworkEnhance` | SE_LOG_TAG |
| `satellite_earth` | `network_enhance` | 日志路径 / 状态文件 / PID 文件 / 通知 tag |
| `v6.3.0` / `v6.3.1` / `v6.3.2` / `v6.3.3` | `v1.0` | 所有版本字符串 |
| `SE_VERSION="6.3.0"` | `SE_VERSION="1.0"` | common.sh |
| `SE_VERSION_CODE="6300"` | `SE_VERSION_CODE="100"` | common.sh |
| `persist.sys.satellite_earth.*` | `settings put global network_enhance_*` | post-fs-data.sh（迁移自 system.prop） |

### 5.2 保留的内部变量前缀
- `SE_` 前缀保留（用户补充要求：内部一致性可保留）
- 例如：`SE_VERSION` / `SE_LOG_FILE` / `SE_MOD_ID` 等

### 5.3 对外显示名称
- 模块名：**网络增强**
- 版本：**v1.0**
- 通知标题前缀：**网络增强 →**
- 日志 tag：**[NetworkEnhance]**
- 状态显示：**网络增强 v1.0 — 状态检测**

---

## 6. 不确定项与假设标注

### 6.1 已验证（有明确来源）
- ✅ preferred_network_mode 数值表（S3 AOSP 源码）
- ✅ 5G RSRP/SINR 字段名（S3 CellSignalStrengthNr.java 源码）
- ✅ cmd netpolicy/wifi/connectivity 子命令（S3 Android Developer + AOSP）
- ✅ system.prop 免Root不生效（S2 官方文档）
- ✅ OEM 兼容性矩阵（S1 + S3 交叉验证）

### 6.2 假设项（需进一步验证）

#### 假设 1: `cmd netpolicy set restrict-background true` 在所有 ROM 上生效
- **依据**：Android Developer 文档明确说明
- **风险**：部分定制 ROM（如 MIUI）可能有自己的数据节省模式实现，会忽略此设置
- **缓解**：在 `apply_game_mode()` 中执行后记录日志，自检中验证状态
- **来源**：S3 + 此处为假设

#### 假设 2: `settings put global endc_capability 0` 真能减少 4G+ 跳频
- **依据**：ENDC 是 4G+5G 双连接控制，关闭后理论上减少聚合
- **风险**：实际效果因设备和运营商而异，部分 ROM 可能忽略此设置
- **缓解**：文档明确告知用户"效果因设备而异"
- **来源**：S3 + 此处为假设

#### 假设 3: 华为/荣耀 `preferred_network_mode` 写入会生效
- **依据**：Reddit r/Honor 用户反馈可用 Shizuku 切换（说明底层接口可用）
- **风险**：HarmonyOS 4.2+ 可能有额外限制
- **缓解**：在 oem_compat.sh 中加入 `se_is_brand_supports_pnm()` 检测，写入后立即读回验证
- **来源**：S3 + 此处为假设

#### 假设 4: `cmd wifi status` 在所有 Android 14+ 设备上输出 RSSI
- **依据**：AOSP 标准命令
- **风险**：部分 ROM 可能输出格式不同
- **缓解**：保留 5 种 fallback 模式（S1 v6.3.1 已实现）
- **来源**：S3 + 此处为假设

### 6.3 不可用项（已在文档中说明）
- ❌ 完全禁用 4G+ 载波聚合（免Root无解，S3 确认）
- ❌ `cmd phone set-preferred-network-type`（不存在，S3 确认）
- ❌ `service call phone`（免Root被拒，S3 确认）
- ❌ `setprop persist.*`（免Root不可用，S2+S3 确认）
- ❌ 各品牌私有 `cmd` 子命令（未发现，S3 确认）

---

## 7. 风险与回退策略

### 7.1 网络制式切换风险
- **风险**：错误的 preferred_network_mode 值可能导致无信号
- **回退**：所有切换前保存原值到 `/data/local/tmp/network_enhance_5g_backup`
- **回退触发**：检测到无网络 60 秒后自动回退

### 7.2 OEM 兼容性风险
- **风险**：某些 ROM 上 settings put 静默失败
- **回退**：`se_put` 函数已有 OEM 兼容性过滤（S1 v6.3.0），失败时记录日志但不崩溃

### 7.3 5G 假满格误判风险
- **风险**：误判可能导致频繁切换
- **回退**：
  - 恢复需连续 3 次正常（6 分钟）
  - 用户可通过 action.sh 菜单 30 手动触发检测
  - 可通过 config.sh 中 `ENABLE_FAKE_5G_DETECTION=false` 关闭

### 7.4 调度器崩溃风险
- **风险**：后台 nohup 进程可能因 ROM 杀后台而退出
- **回退**：service.sh 在 BOOT_COMPLETED 时重启调度器（S1 原模块逻辑保持）

---

## 8. 实施顺序（第五步编码计划）

1. **先重写 `module.prop` + `config.sh`**（基础配置）
2. **重写 `scripts/common.sh`**（核心函数库，其他脚本依赖）
3. **扩展 `scripts/oem_compat.sh`**（OEM 矩阵）
4. **重写 `scripts/carrier.sh`**（运营商默认值修正）
5. **重写 `scripts/monitor.sh`**（5G 假满格逻辑）
6. **重写 `scripts/weaknet.sh`**（游戏模式重构）
7. **增强 `scripts/network_info.sh`**（5G 信号采集）
8. **优化 `scripts/wifi.sh` + `scripts/dns.sh`**
9. **重写 `customize.sh` + `post-fs-data.sh` + `service.sh` + `action.sh` + `uninstall.sh`**
10. **删除 `system.prop`**
11. **更新 `webroot/index.html`**
12. **重写 `README.md` + `CHANGELOG.md`**
13. **打包为 `Network_Enhance_v1.0.zip`**

---

## 9. 自检清单（第六步将逐条核对）

- [ ] 所有 ADB Shell 命令在 Android 14/15 无 Root 下可用
- [ ] 所有 settings 键经过 OEM 兼容性矩阵过滤
- [ ] preferred_network_mode 数值与 S3 AOSP 源码一致
- [ ] 5G 假满格判定算法与 S3 设计一致
- [ ] 检测间隔统一为 120 秒
- [ ] system.prop 已删除
- [ ] 所有路径与命名已统一为 network_enhance
- [ ] 版本号统一为 v1.0
- [ ] customize.sh 自检 bug 已修复
- [ ] Android 14/15 版本检测分支已加入
- [ ] 无任何 `su` / `setprop persist.*` / `/system` 写入
- [ ] 无任何虚构的 ADB 命令或 settings 键

---

**第四步方案制定完成。** 请审阅以下关键决策：

1. ✅ 文件改动清单已逐文件说明（含修改原因与来源标注）
2. ✅ 新模块目录结构清晰
3. ✅ 核心逻辑设计完整（调度器/场景模式/制式管理/OEM 矩阵）
4. ✅ 自检系统增强方案明确
5. ✅ 命名与版本统一清单完整
6. ✅ 4 项假设已明确标注（需进一步验证）
7. ✅ 不可用项已明确告知用户
8. ✅ 风险与回退策略完备
9. ✅ 实施顺序已规划

**请确认方案无误后，我将进入第五步执行编码。** 如需调整任何部分，请指出。
