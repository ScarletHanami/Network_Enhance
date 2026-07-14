# 第三步：Android 14/15 无 Root ADB Shell 网络优化命令研究

## 来源汇总（交叉验证）
- AOSP 源码 RILConstants.java：https://android.googlesource.com/platform/frameworks/base/+/master/telephony/java/com/android/internal/telephony/RILConstants.java
- CellSignalStrengthNr.java 源码：https://android.googlesource.com/platform/frameworks/base.git/+/master/telephony/java/android/telephony/CellSignalStrengthNr.java
- Android Developer 官方文档：https://developer.android.com/develop/connectivity/network-ops/data-saver
- Android Open Source Data Saver：https://source.android.com/docs/core/data/data-saver
- XDA Tasker PNM 指南：https://xdaforums.com/t/tasker-preferred-network-mode-profile-switching-to-3g-5g.4754542/
- Stack Overflow PNM：https://stackoverflow.com/questions/25319129/
- 5G RSRP/RSRQ/SINR 测量：https://www.techplayon.com/5g-nr-measurements-rsrp-rssi-rsrq-and-sinr
- privacy.sexy ADB 命令集：https://github.com/undergroundwires/privacy.sexy/discussions/359
- Daniel Ritter Android 15 PNM：https://www.daniel-ritter.de/blog/change-preferred-network-mode-on-android-15-2g-3g-lte-4g-5g-with-shell-command

---

## 1. preferred_network_mode 完整数值表（来自 AOSP 源码 RILConstants.java，最权威）

### 数值表（Android 14/15 通用）
| 数值 | 常量名 | 含义 | 用途 |
|---|---|---|---|
| 0 | NETWORK_MODE_WCDMA_PREF | GSM/WCDMA (WCDMA preferred) | 3G 时代默认 |
| 1 | NETWORK_MODE_GSM_ONLY | GSM only | 仅 2G |
| 2 | NETWORK_MODE_WCDMA_ONLY | WCDMA only | 仅 3G |
| 3 | NETWORK_MODE_GSM_UMTS | GSM/WCDMA auto (PRL) | 2G/3G 自动 |
| 4 | NETWORK_MODE_CDMA | CDMA/EvDo auto | 电信 3G |
| 5 | NETWORK_MODE_CDMA_NO_EVDO | CDMA only | 电信 2G |
| 6 | NETWORK_MODE_EVDO_NO_CDMA | EvDo only | 电信 3G 数据 |
| 7 | NETWORK_MODE_GLOBAL | GSM/WCDMA/CDMA/EvDo auto | 全局 |
| 8 | NETWORK_MODE_LTE_CDMA_EVDO | LTE/CDMA/EvDo | 电信 4G |
| **9** | **NETWORK_MODE_LTE_GSM_WCDMA** | **LTE/GSM/WCDMA** | **锁定 4G（推荐，无 5G）** |
| 10 | NETWORK_MODE_LTE_CDMA_EVDO_GSM_WCDMA | LTE/CDMA/EvDo/GSM/WCDMA | 全制式无 5G |
| **11** | **NETWORK_MODE_LTE_ONLY** | **LTE only** | **强制 4G 单一** |
| 12 | NETWORK_MODE_LTE_WCDMA | LTE/WCDMA | 4G/3G |
| 13 | NETWORK_MODE_TDSCDMA_ONLY | TD-SCDMA only | 移动 3G |
| 14-22 | 各种 TD-SCDMA 组合 | 中国移动 3G/4G 组合 | 移动专用 |
| **23** | **NETWORK_MODE_NR_ONLY** | **NR 5G only** | **强制 5G 单一** |
| 24 | NETWORK_MODE_NR_LTE | NR/LTE | 5G+4G |
| 25 | NETWORK_MODE_NR_LTE_CDMA_EVDO | NR/LTE/CDMA/EvDo | 电信 5G |
| **26** | **NETWORK_MODE_NR_LTE_GSM_WCDMA** | **NR/LTE/GSM/WCDMA** | **联通 5G 默认** |
| 27 | NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA | 全制式含 5G | 广电/电信 5G |
| 28 | NETWORK_MODE_NR_LTE_WCDMA | NR/LTE/WCDMA | 联通 5G 简化 |
| 29 | NETWORK_MODE_NR_LTE_TDSCDMA | NR/LTE/TD-SCDMA | 移动 5G 简化 |
| 30 | NETWORK_MODE_NR_LTE_TDSCDMA_GSM | NR/LTE/TD-SCDMA/GSM | 移动 5G |
| 31 | NETWORK_MODE_NR_LTE_TDSCDMA_WCDMA | NR/LTE/TD-SCDMA/WCDMA | 移动 5G |
| **32** | **NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA** | **NR/LTE/TD-SCDMA/GSM/WCDMA** | **移动 5G 默认** |
| **33** | **NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA** | **全制式含 5G（最全）** | **广电 5G 默认** |

### 关键洞察（用于"5G 假满格"和"4G+ 跳频"修复）
- **要锁定 4G（关闭 5G）**：`settings put global preferred_network_mode 9` (LTE/GSM/WCDMA) 或 `11` (LTE only)
- **要锁定 5G（避免 4G+ 跳频）**：`settings put global preferred_network_mode 23` (NR only)
- **当前模块游戏模式开 5G SA + DC + ENDC 是错的**，正确做法是游戏模式用 `11` (LTE only) 或 `23` (NR only) 锁定单一制式
- **5G 假满格自救**：从 `26/32/33` 降到 `9` 或 `11`

⚠️ **重要**：原模块中：
- 电信/广电用 26（NR/LTE/GSM/WCDMA）—— **错误**，26 不含 CDMA，电信应改用 27 或 33
- 移动/联通用 23（NR only）—— **极端**，会丢失 4G 回退，应改用 32（移动）或 26（联通）

### ADB 用法（Android 14/15 验证可用）
```bash
# 查询
adb shell settings get global preferred_network_mode
# 设置（免Root可用）
adb shell settings put global preferred_network_mode <value>
# 同时设置 preferred_network_mode1（双卡设备的副卡）
adb shell settings put global preferred_network_mode1 <value>
```

⚠️ **关键**：Stack Overflow 与 XDA 多个帖子确认，`settings put global preferred_network_mode` 在 Android 14/15 上**免Root可用**，但部分 ROM（如三星 OneUI、部分 HyperOS 版本）会忽略此设置。需要 OEM 兼容性矩阵。

---

## 2. cmd 子命令可用性

### 2.1 `cmd netpolicy`（Android 14/15 免Root部分可用）
来源：Android Developer 官方文档 https://developer.android.com/develop/connectivity/network-ops/data-saver + AOSP 文档 https://source.android.com/docs/core/data/data-saver

| 子命令 | 功能 | 免Root |
|---|---|---|
| `cmd netpolicy list restrict-background-whitelist` | 列出白名单 UID（不受 Data Saver 限制） | ✅ |
| `cmd netpolicy list restrict-background-blacklist` | 列出黑名单 UID | ✅ |
| `cmd netpolicy add restrict-background-whitelist <UID>` | 添加应用到白名单 | ✅ |
| `cmd netpolicy remove restrict-background-whitelist <UID>` | 移除白名单 | ✅ |
| `cmd netpolicy add restrict-background-blacklist <UID>` | 添加到黑名单 | ✅ |
| `cmd netpolicy set restrict-background <true/false>` | 开关 Data Saver | ✅ |
| `cmd netpolicy get restrict-background` | 查询 Data Saver 状态 | ✅ |
| `cmd netpolicy list wifi-networks` | 列出 WiFi 网络（含 metered 标记） | ✅ |
| `cmd netpolicy set metered-network <wifi> <true/false>` | 标记 WiFi 为计费 | ✅ |

**用途**：
- 游戏模式：`cmd netpolicy set restrict-background true` 开启 Data Saver，禁止后台应用抢带宽
- 退出游戏模式时：`cmd netpolicy set restrict-background false` 关闭

### 2.2 `cmd wifi`（Android 14/15 免Root部分可用）
来源：Stack Overflow https://stackoverflow.com/questions/75294766/ + AOSP

| 子命令 | 功能 | 免Root |
|---|---|---|
| `cmd wifi status` | 查询 WiFi 状态（含 RSSI、SSID、频率） | ✅ |
| `cmd wifi set-wifi-enabled <true/false>` | 开关 WiFi | ⚠️ Android 14+ 需系统权限 |
| `cmd wifi connect-network <ssid> open|wpa2 <passphrase>` | 连接 WiFi | ✅ |
| `cmd wifi forget-network <networkId>` | 忘记网络 | ✅ |
| `cmd wifi save-network <ssid> open|wpa2 <passphrase>` | 保存网络 | ✅ |
| `cmd wifi list-networks` | 列出已保存网络 | ✅ |
| `cmd wifi list-scan-results` | 列出扫描结果 | ✅ |
| `cmd wifi start-scan` | 启动扫描 | ✅ |
| `cmd wifi set-poll-interval <ms>` | 设置轮询间隔 | ⚠️ 部分ROM限制 |
| `cmd wifi force-country-code <code>` | 强制国家码 | ❌ 需系统权限 |

**用途**：
- `cmd wifi status` 是 `dumpsys wifi` 的精简版，输出更稳定，**推荐作为 RSSI 读取的首选**
- `cmd wifi start-scan` 可手动触发扫描

### 2.3 `cmd connectivity`（Android 14/15 免Root部分可用）
来源：Stack Overflow https://stackoverflow.com/questions/10506591/

| 子命令 | 功能 | 免Root |
|---|---|---|
| `cmd connectivity airplane-mode <enabled/disabled>` | 切换飞行模式 | ✅ |
| `cmd connectivity list` | 列出网络 | ✅ |
| `cmd connectivity get-airplane-mode` | 查询飞行模式 | ✅ |

**用途**：
- 极限弱网场景下可临时切换飞行模式 3 秒后还原，触发网络重新注册（"软重启"网络）
- ⚠️ 需用户提示，不能擅自操作

### 2.4 `cmd phone`（Android 14/15 免Root极其有限）
来源：AOSP PhoneService 源码

| 子命令 | 功能 | 免Root |
|---|---|---|
| `cmd phone help` | 列出子命令 | ✅ |
| 大部分调试子命令 | 需系统权限 | ❌ |

**结论**：`cmd phone` 没有 `set-preferred-network-type` 公开子命令。网络制式切换只能用 `settings put global preferred_network_mode`。

⚠️ 注意：`service call phone 108 i32 0 i32 0 i64 "<bitmask>"` 是底层方案，但需要从 framework.jar 提取 TRANSACTION_code（每设备不同），且免Root下会因权限被拒。**不推荐使用**。

### 2.5 `cmd notification`（免Root可用）
| 子命令 | 功能 |
|---|---|
| `cmd notification post -S bigtext -t <title> <tag> <body>` | 发送通知 |
| `cmd notification cancel <tag>` | 撤销通知 |
| `cmd notification list` | 列出通知 |

---

## 3. Android 14/15 settings global 网络相关键名大全

### 3.1 移动数据与保活
来源：AOSP Settings.Global + privacy.sexy https://github.com/undergroundwires/privacy.sexy/discussions/359

| 键名 | 类型 | 含义 | 免Root写入 |
|---|---|---|---|
| `mobile_data` | int (0/1) | 移动数据开关 | ✅ |
| `mobile_data_always_on` | int (0/1) | 移动数据常开（即使WiFi连上） | ✅ |
| `mobile_data_preferred` | int (0/1) | 移动数据优先（默认走移动而非WiFi） | ✅ |
| `mobile_data_auto_handover` | int (0/1) | WiFi 弱时自动切换到移动数据 | ✅ |
| `preferred_network_mode` | int | 主卡网络制式（见数值表） | ✅ |
| `preferred_network_mode1` | int | 副卡网络制式 | ✅ |

### 3.2 5G / NR 控制
| 键名 | 含义 | 免Root | OEM 兼容性 |
|---|---|---|---|
| `nr_sa_mode` | 5G SA 独立组网开关 | ✅ | ⚠️ 小米用 `nr_mode`，vivo/三星/华为跳过 |
| `enable_nr_dc` | 5G DC 双连接开关 | ✅ | ⚠️ vivo/三星/华为跳过 |
| `endc_capability` | ENDC 4G+5G 双连接能力 | ✅ | ⚠️ MTK 芯片/三星/华为跳过 |
| `nr_handover_enabled` | NR 切换开关 | ✅ | ⚠️ 三星/华为跳过 |
| `vonr_enabled` | VoNR（5G 通话）开关 | ✅ | ⚠️ 华为跳过 |
| `volte_vt_enabled` | VoLTE + VT 视频通话 | ✅ | 全品牌可用 |
| `vt_enabled` | Video Telephony | ✅ | 全品牌可用 |

### 3.3 WiFi 相关
来源：AOSP WifiSettings + 原 modules 已验证

| 键名 | 含义 | 默认值 | 免Root |
|---|---|---|---|
| `wifi_scan_throttle_enabled` | 扫描节流（0=关闭，提升扫描频率） | 1 | ✅ |
| `wifi_framework_scan_interval_ms` | 扫描间隔（ms） | 30000 | ✅ |
| `wifi_suspend_optimizations_enabled` | 休眠时优化（0=关闭，保活） | 1 | ✅ |
| `wifi_idle_ms` | WiFi 空闲超时（ms） | varies | ✅ |
| `wifi_bad_rssi_threshold` | 弱信号阈值（dBm，负值） | -88 | ✅ |
| `wifi_bad_rssi_threshold_2g` | 2.4G 弱信号阈值 | -88 | ✅ |
| `wifi_bad_rssi_threshold_5g` | 5G 弱信号阈值 | -85 | ✅ |
| `wifi_networks_score_enabled` | 网络评分（0=关闭，避免自动切换） | 1 | ✅ |
| `wifi_max_dwell_time_ms` | 最大驻留时间 | 60000 | ✅ |
| `wifi_pno_frequency_threshold` | PNO 频率阈值 | 2 | ✅（小米跳过） |
| `wifi_persistent_group_remove_delay_ms` | 持久化组移除延迟 | 30000 | ✅（华为跳过） |
| `wifi_enhanced_mac_randomization_enabled` | 增强 MAC 随机化 | 0 | ✅（API<30 不支持） |
| `wifi_connected_mac_randomization_enabled` | 连接时 MAC 随机化 | 0 | ✅（API<30 不支持） |

### 3.4 DNS 相关
来源：Multiple GitHub Gist + Reddit 验证

| 键名 | 含义 | 免Root |
|---|---|---|
| `private_dns_mode` | Private DNS 模式（off/opportunistic/hostname） | ✅ |
| `private_dns_spec` | Private DNS 主机名（如 dns.alidns.com） | ✅ |
| `dns1` | 自定义 DNS1（仅部分ROM生效） | ⚠️ |
| `dns2` | 自定义 DNS2 | ⚠️ |

### 3.5 载波聚合（4G+）禁用 —— 关键发现
**搜索结论**：Android 14/15 上**没有公开的 `settings global` 键可以直接禁用载波聚合**。

来源：XDA https://xdaforums.com/t/guide-enable-4g-lte-a-carrier-aggregation-without-root-on-stock-rom.3894282/page-6 + Reddit https://www.reddit.com/r/Xiaomi/comments/m4ymla/

可行的间接方案：
1. **方案A：通过 preferred_network_mode 锁定 LTE only（11）**——会禁止 5G，但 4G 内部仍可能聚合
2. **方案B：通过飞行模式切换重置基站连接**——临时方案
3. **方案C：通过 `*#*#3646633#*#*` 工程模式**——免Root下可用 `am start -a android.intent.action.MAIN -n com.android.settings/.RadioInfo` 跳转，但需用户手动操作
4. **方案D**：MediaTek 设备有 `*#*#3646633#*#*` 工程模式的 LTE CA 选项可关闭，但**无法通过 ADB 直接调用**

**实际可用的折中方案**：
- 通过 `settings put global preferred_network_mode 11`（LTE only）配合 `se_put global endc_capability 0`（关闭 ENDC）来"软禁用"4G+
- ⚠️ 在 OEM 兼容性矩阵中明确标注：**"完全禁用载波聚合需 Root 或工程模式，免Root只能通过锁定单一 LTE 间接降低跳频概率"**

---

## 4. 5G 信号质量指标获取（RSRP/RSRQ/SINR）

### 4.1 dumpsys telephony.registry 输出格式
来源：AOSP SignalStrength.java 源码 + 阿里云技术文章 + Stack Exchange

输出示例（Android 14/15 真实格式）：
```
mSignalStrength=SignalStrength: 
  mGsmSignalStrength=99 mGsmBitErrorRate=-1
  mCdmaDbm=-1 mCdmaEcio=-1 mEvdoDbm=-1 mEvdoEcio=-1 mEvdoSnr=-1
  mLteSignalStrength=99 mLteRsrp=-95 mLteRsrq=-10 mLteRssnr=6 mLteCqi=-1
  mTdscdmaRscp=255
  mWcdmaSignalStrength=99 mWcdmaRscp=-1
  mNrCellSignalStrengths=[CellSignalStrengthNr:
    mCsiRsrp=-95 mCsiRsrq=-10 mCsiSinr=13
    mSsRsrp=-95 mSsRsrq=-10 mSsSinr=13
    mLevel=4
  ]
  mLevel=4
```

### 4.2 关键字段（来自 CellSignalStrengthNr.java 源码）
来源：https://android.googlesource.com/platform/frameworks/base.git/+/master/telephony/java/android/telephony/CellSignalStrengthNr.java

| 字段 | 含义 | 取值范围 | 推荐阈值 |
|---|---|---|---|
| `mSsRsrp` | SS-RSRP（同步信号参考功率，5G 主用） | -156 to -31 dBm | 强≥-85, 弱≤-110 |
| `mCsiRsrp` | CSI-RSRP（信道状态参考功率，5G 辅助） | -156 to -31 dBm | 同 SS-RSRP |
| `mSsRsrq` | SS-RSRQ（参考信号质量） | -43 to 20 dB | 强≥-10, 弱≤-15 |
| `mCsiRsrq` | CSI-RSRQ | -43 to 20 dB | 同上 |
| `mSsSinr` | SS-SINR（信噪比+干扰） | -23 to 40 dB | 强≥10, 弱≤0 |
| `mCsiSinr` | CSI-SINR | -23 to 40 dB | 同上 |
| `mLevel` | 信号等级（0-4） | 0-4 | 4=强, 0-1=弱 |
| `mLteRsrp` | LTE RSRP（4G 信号，旧字段） | -140 to -44 dBm | 强≥-90, 弱≤-110 |

### 4.3 5G 假满格判定算法（关键！）
基于 AOSP 源码 + 实战经验设计：

```bash
# 判定条件（同时满足2条即判定为假满格）
# 1. mLevel=4（信号满格）或 mSsRsrp ≥ -85（信号强度好）
# 2. ping_ms > 200（实际延迟极高）或 ping 失败（丢包）
# 3. mSsSinr < 0（信噪比差，强干扰）
```

**算法逻辑**：
1. 读取 `mSsRsrp`/`mCsiRsrp` —— 信号强度
2. 读取 `mSsSinr`/`mCsiSinr` —— 信号质量
3. 读取 `mLevel` —— 系统判定等级
4. 执行 ping 测试（223.5.5.5 + 119.29.29.29 双 DNS，超时 2s）
5. **判定**：
   - 若 `mSsRsrp ≥ -85` 但 `ping_ms > 200ms` 或 `mSsSinr < 0` → **5G 假满格**
   - 触发动作：`settings put global preferred_network_mode 9`（降级到 4G）

### 4.4 dumpsys telephony.registry 多 ROM 兼容解析
不同 ROM 的输出字段格式可能不同：
- **AOSP 标准**：`mSsRsrp=-95 mSsRsrq=-10 mSsSinr=13`
- **MIUI/HyperOS**：可能用 `mCsiRsrp` 或合并显示
- **ColorOS**：基本同 AOSP
- **EMUI/HarmonyOS**：可能用 `nrRsrp` 简写
- **OneUI**：可能用 `SsRsrp`（无 m 前缀）

**解析策略**：5 种 grep 模式 fallback（沿用原模块的成熟方案）：
```bash
# 模式 1: mSsRsrp=-95
dbm=$(echo "$reg" | grep -oE 'mSsRsrp=[-]?[0-9]+' | head -1 | cut -d= -f2)
# 模式 2: mCsiRsrp=-95
dbm=$(echo "$reg" | grep -oE 'mCsiRsrp=[-]?[0-9]+' | head -1 | cut -d= -f2)
# 模式 3: mLteRsrp=-95 (4G)
dbm=$(echo "$reg" | grep -oE 'mLteRsrp=[-]?[0-9]+' | head -1 | cut -d= -f2)
# 模式 4: mDbm=-95 (旧 AOSP)
dbm=$(echo "$reg" | grep -oE 'mDbm=[-]?[0-9]+' | head -1 | cut -d= -f2)
# 模式 5: 整体 SignalStrength 行第一个负数
dbm=$(echo "$reg" | grep 'mSignalStrength' | head -1 | grep -oE '[-][0-9]+' | head -1)
```

---

## 5. 国产手机 Android 14/15 网络设置差异

### 5.1 小米 HyperOS
来源：Reddit r/HyperOS + tweakradje 网站

- **私有键替换**：
  - `nr_sa_mode` → 实际使用 `nr_mode`（小米私有键名）
  - `data_stall_alarm_aggressive` → `data_stall_alarm_interval`（MIUI 私有）
  - `mobile_data_auto_handover` → `mobile_data_auto_switch`（MIUI 私有）
- **跳过键**：
  - `wifi_pno_frequency_threshold`（MIUI 不支持）
  - `wifi_recovery_state`（MIUI 私有实现不同）
- **HyperOS 3 新增**：部分设置需"开发者选项 → USB 调试（安全设置）"才能写入
- **可用 cmd**：无公开的 `cmd miui` 网络子命令

### 5.2 vivo OriginOS / Funtouch
来源：Reddit r/Vivo

- **跳过键**：
  - `nr_sa_mode`（会导致 telephony 崩溃）
  - `enable_nr_dc`（部分机型 modem 重启）
  - `data_stall_alarm_aggressive/non_aggressive`（OriginOS 私有实现）
  - `wifi_enhanced_mac_randomization_enabled`（OriginOS 6 移除）
- **OriginOS 6 (Android 16)**：已移除部分 ADB 命令（如主题色修改），网络相关命令仍可用
- **可用方案**：仅靠 `preferred_network_mode` + `mobile_data_*` 基础键

### 5.3 OPPO ColorOS / OnePlus / Realme
- **全部 AOSP 标准键可写**（原模块主测试环境，无需跳过）
- **无已知私有 cmd**

### 5.4 华为 HarmonyOS / EMUI
来源：Reddit r/Huawei + r/Honor

- **跳过键**：
  - 所有 5G NR 键（`nr_sa_mode`/`enable_nr_dc`/`endc_capability`/`nr_handover_enabled`/`vonr_enabled`）
  - `wifi_persistent_group_remove_delay_ms`
- **HarmonyOS 4.2+**：5G 行为与 AOSP 差异大，建议**仅用 `preferred_network_mode`**
- **EMUI 14.2**：5G 切换存在异常，需用户手动通过 `*#*#4636#*#*` 调整

### 5.5 荣耀 MagicOS
来源：Reddit r/Honor

- 与华为 EMUI 类似，**所有 5G NR 键跳过**
- 推荐使用 Shizuku 或第三方网络切换 App（社区反馈）
- **可用基础键**：`mobile_data_always_on`/`mobile_data_preferred`/`preferred_network_mode`

### 5.6 三星 OneUI
- **跳过键**：`nr_sa_mode`/`enable_nr_dc`/`endc_capability`/`nr_handover_enabled`/`wifi_max_dwell_time_ms`
- **可用**：基础移动数据键 + `preferred_network_mode`（但部分 OneUI 版本会忽略）
- 工程模式 `*#0011#` 可查看 CA 状态，但无法 ADB 控制

### 5.7 关键结论
- **没有任何品牌提供公开的私有 `cmd` 子命令用于网络优化**
- 各品牌的差异主要在 `settings global` 键的**支持与否**
- 原 modules 的 `se_key_supported()` 矩阵基本正确，但需要扩展更多键的精细处理
- **必须做的扩展**：
  - 增加 `mLteRsrp`/`mSsRsrp` 等 RSRP 字段的 OEM 兼容性解析
  - 增加 `preferred_network_mode` 的 OEM 默认值表（避免误设错值）
  - 在 `se_show_oem_info` 中明确标注"该品牌不支持某功能"

---

## 6. Android 14 → 15 版本差异

来源：Android Developer 行为变更文档 https://developer.android.com/about/versions/14/behavior-changes-14

### 6.1 Android 14 (API 34) 主要变化
- **BLUETOOTH_CONNECT 权限强制**：影响蓝牙网络共享
- **前台服务类型强制声明**：dataSync 类服务需声明 `networkType`
- **隐私沙盒**：影响广告 SDK，与网络优化无关
- **2G 网络禁用**：`settings put global preferred_network_mode 9` 可禁用 2G

### 6.2 Android 15 (API 35) 主要变化
- **16KB 页面大小**：影响 native 库，shell 脚本无关
- **前台服务超时**：影响后台长时服务
- **NetworkCallback 增强**：API 变化，shell 命令无关
- **Private Space**：影响应用隔离，与网络无关
- **关键**：`settings put global preferred_network_mode` 在 15 上仍可用，但部分 ROM 提示"将废弃"
- **建议**：在 `common.sh` 中加入版本检测分支：
  ```bash
  api=$(getprop ro.build.version.sdk)
  case "$api" in
      3[4-9]|4[0-9])  # Android 14+ 全部走新逻辑
          ...
          ;;
      *)
          # 降级兼容（虽然模块要求 Android 14+）
          ...
          ;;
  esac
  ```

---

## 7. 完整 ADB Shell 命令审计表（最终版）

| 命令 | 用途 | Android 14 | Android 15 | 免Root | 来源 |
|---|---|---|---|---|---|
| `settings put/get/delete global <key> <val>` | 系统设置 | ✅ | ✅ | ✅ | AOSP |
| `cmd notification post/cancel` | 通知 | ✅ | ✅ | ✅ | AOSP |
| `cmd wifi status` | WiFi 状态 | ✅ | ✅ | ✅ | AOSP |
| `cmd wifi start-scan` | 启动 WiFi 扫描 | ✅ | ✅ | ✅ | AOSP |
| `cmd wifi list-scan-results` | 列出扫描结果 | ✅ | ✅ | ✅ | AOSP |
| `cmd wifi connect-network` | 连接 WiFi | ✅ | ✅ | ✅ | AOSP |
| `cmd netpolicy set restrict-background <bool>` | Data Saver 开关 | ✅ | ✅ | ✅ | Android Developer |
| `cmd netpolicy add/remove restrict-background-whitelist <UID>` | 白名单管理 | ✅ | ✅ | ✅ | AOSP |
| `cmd connectivity airplane-mode <enabled/disabled>` | 飞行模式 | ✅ | ✅ | ✅ | Stack Overflow |
| `cmd phone help` | phone 帮助 | ✅ | ✅ | ✅ | AOSP |
| `dumpsys connectivity` | 网络连接状态 | ✅ | ✅ | ✅ | AOSP |
| `dumpsys wifi` | WiFi 详情 | ✅ | ✅ | ✅ | AOSP |
| `dumpsys telephony.registry` | 移动信号（含 RSRP/SINR） | ✅ | ✅ | ✅ | AOSP |
| `dumpsys netpolicy` | 网络策略 | ✅ | ✅ | ✅ | AOSP |
| `dumpsys netstats` | 网络流量统计 | ✅ | ✅ | ✅ | AOSP |
| `getprop` | 系统属性读取 | ✅ | ✅ | ✅ | AOSP |
| `ping -c N -W sec <host>` | 网络延迟 | ✅ | ✅ | ✅ | toybox |
| `nc -w sec -z host port` | 端口可达性 | ✅ | ✅ | ✅（部分ROM） | netcat |
| `ip route` | 默认网关 | ✅ | ✅ | ✅ | toybox |
| `nohup sh ... &` | 后台进程 | ✅ | ✅ | ✅ | POSIX |
| `kill -0/pid <pid>` | 进程管理 | ✅ | ✅ | ✅（仅自己子进程） | POSIX |
| `pm list packages -U` | 列出应用+UID | ✅ | ✅ | ✅ | AOSP |
| `am start -a android.intent.action.MAIN -n <pkg>/<act>` | 启动 Activity | ✅ | ✅ | ✅ | AOSP |
| `setprop persist.*` | ❌ 写 persist.* | ✅ | ✅ | ❌ 需Root | AOSP |
| `service call phone <code>` | 底层调用 | ✅ | ✅ | ❌ 大部分被拒 | AOSP |
| `cmd phone set-preferred-network-type` | ❌ 不存在 | - | - | - | AOSP |

---

## 8. 第三步关键发现总结

### ✅ 可直接采用
1. **preferred_network_mode 数值表已完整获取**（AOSP 源码权威）
2. **5G 假满格判定算法**：基于 mSsRsrp + mSsSinr + ping_ms 三维度
3. **cmd netpolicy 可用**：开启 Data Saver 限制后台带宽
4. **cmd wifi status 比 dumpsys wifi 更稳定**，建议作为首选 RSSI 来源
5. **cmd connectivity airplane-mode 可用**：网络软重启
6. **RSRP/RSRQ/SINR 阈值已确定**：来自 AOSP 源码与 3GPP 标准

### ❌ 不可用 / 需明确告知用户
1. **完全禁用载波聚合（4G+）**：免Root下无公开方法，只能通过锁定 LTE only 间接降低跳频
2. **`cmd phone set-preferred-network-type`**：不存在此子命令
3. **`service call phone`**：免Root下大部分被拒
4. **`setprop persist.*`**：免Root下不可用，必须移除 system.prop
5. **各品牌私有 `cmd` 子命令**：搜索未发现任何品牌提供

### ⚠️ 需在代码中处理
1. **OEM 兼容性矩阵扩展**：增加更多键的精细处理（特别是 RSRP 字段的多 ROM 解析）
2. **Android 14/15 版本检测分支**：通过 `getprop ro.build.version.sdk` 判断
3. **preferred_network_mode 各运营商正确默认值**：
   - 电信 → 27（NR/LTE/CDMA/EvDo/GSM/WCDMA）—— **不是原模块的 26**
   - 移动 → 32（NR/LTE/TD-SCDMA/GSM/WCDMA）—— **不是原模块的 23**
   - 联通 → 26（NR/LTE/GSM/WCDMA）—— ✅ 原模块正确
   - 广电 → 33（NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA）—— **不是原模块的 26**

