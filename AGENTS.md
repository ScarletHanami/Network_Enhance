# AGENTS.md — 项目上下文指南

> ⚠️ **重要：AGENTS.md 是"活文档"** — 任何代码变更（新增/修改/删除功能、重构、调整架构）后，**应考虑同步更新本文档**，确保其反映代码真实状态。过时的 AGENTS.md 可能误导协作者。

## 项目概况

**Network_Enhance (AxManager 网络增强模块)**

中国大陆网络优化模块，基于 AxManager 免 Root ADB 权限运行。专为 Android 14+ 国产手机设计，提供 5G 假满格降级、游戏模式 LTE 锁定、代理稳定模式、智能 DNS、WiFi 优化等能力。

- **运行环境**: AxManager (ADB shell, `#!/system/bin/sh`)
- **最低 Android**: 14 (API 34)
- **当前版本**: 见 `module.prop` 中的 `version` 和 `versionCode` 字段
- **CI 构建版本**: CI 构建产物中 `version` 字段被替换为 `v<timestamp>`（如 `v20260719_120000`），`versionCode` 被替换为日期数字（如 `20260719`），与 artifact 名称保持一致
- **支持的品牌**: 小米/HyperOS, OPPO/ColorOS, vivo/OriginOS, 华为/HarmonyOS, 荣耀/MagicOS, 三星/OneUI
- **技术约束**: 无 Root 权限，所有操作基于 `settings put/get`、`cmd wifi/netpolicy`、`getprop/setprop`、`dumpsys`

---

## 目录结构

```
Network_Enhance/          # 项目根目录（即模块发布根目录）
├── scripts/                      # 功能脚本（9 个）
│   ├── common.sh                 # 核心函数库（1360+ 行）
│   ├── oem_compat.sh             # OEM 兼容性矩阵
│   ├── monitor.sh                # 动态调度器
│   ├── carrier.sh                # 运营商优化 + 制式管理
│   ├── network_info.sh           # 网络状态采集（JSON 输出）
│   ├── weaknet.sh                # 弱网自救 + 代理稳定模式
│   ├── wifi.sh                   # WiFi 专用优化
│   ├── dns.sh                    # Private DNS 管理
│   └── diag_dump.sh              # 诊断数据抓取（开发调试用）
├── webroot/index.html            # WebUI 控制面板
├── action.sh                     # 用户菜单入口（35 项）
├── config.sh                     # 用户配置中心
├── customize.sh                  # 安装脚本
├── post-fs-data.sh               # BOOT_COMPLETED first sync
├── service.sh                    # BOOT_COMPLETED late_start
├── uninstall.sh                  # 卸载清理
├── module.prop                   # AxManager 模块清单
├── banner.png                    # 模块横幅图
├── CHANGELOG.md                  # 版本变更日志
├── LICENSE                       # MIT 许可证
├── README.md                     # 模块项目主页 README
├── AGENTS.md                     # 本文件
└── .gitignore                    # Git 忽略规则
```

---

## 代码约定

注意代码修改后视情况更新 `AGENTS.md`

### Shell 脚本规范

| 规约 | 要求 |
|------|------|
| **Shebang** | `#!/system/bin/sh`（Android 环境） |
| **双引号引用** | 所有 shell 变量引用必须用双引号包裹（`"$var"`），防止词分割 |
| **默认值保护** | `"${var:-default}"` 模式为所有变量提供默认值 |
| **函数风格** | `func_name() { ... }`（小写+下划线） |
| **本地变量** | 函数内部 `local var` 声明，避免全局污染 |
| **错误处理** | `|| return $?` 传播关键错误，不静默吞掉 |
| **日志** | 用 `log_msg()` 函数统一输出，标签为 `[core]`/`[boot]`/`[warn]`/`[oem]` 等 |

### 注释规范

- **函数文档**: 只写 WHY，不写 HOW（代码本身说明实现）
- **无追踪标记**: 禁止 `⚠️ 修改点 N:`、`来源: Sx` 等开发过程标记
- **有价值的注释**:
  - 非显而易见的决策理由（如"此处不关闭 enable_nr_dc 是为了快速恢复 5G"）
  - AOSP 源码参考（如"RILConstants.java 数值表"）
  - OEM 特殊行为说明（如"vivo 上 nr_sa_mode 写入会崩溃"）
  - 跨文件协作关系（如"与 lock_lte 共用 $SE_5G_BACKUP_FILE"）
- **内联注释**: 仅当代码意图不直观时使用，自明代码不加注释

### WebUI (index.html) 规范

- 单 `index.html` 文件，内嵌 CSS + JavaScript
- 通过 `window.networkBridge` 与 AxManager 通信
- 所有 API 调用经 `networkBridge.call()` 封装
- 状态轮询用 `setInterval` + `fetchStatus()`

---

## 关键架构决策

### 1. 免 Root 能力边界

| 无法实现 | 替代方案 |
|----------|----------|
| 完全禁用 4G+ CA | 锁 LTE Only + 关 ENDC 间接降低概率 |
| `setprop persist.*` | 已移除 system.prop，改用 `settings put global` |
| `service call phone` | 通过 `settings put global preferred_network_mode` 间接切换 |
| 各品牌私有 cmd 子命令 | 无可用公开命令 |

### 2. 调度器架构

```
monitor.sh（主循环，120s 周期）
├── 5G 假满格检测 → handle_fake_5g() → degrade_5g_to_4g()
├── 网络等级判定 → compute_overall_level_v2()
├── 动态参数计算 → se_compute_dynamic_params()
├── 无网络回退 → handle_no_network_rollback()
└── 弱网隔离 → weaknet 激活时跳过整轮
```

- 与 `weaknet.sh` 严格隔离：weaknet 激活时监控器不做任何 PNM 操作（三重防护：主循环 continue + 函数入口检查 × 2）
- 防振荡冷却：降级后 30 分钟冷却期，结束后连续 3 次正常才恢复
- 无网络死锁回退：降级到 4G 后连续 2 次 Ping 完全失败，自动恢复 5G

### 3. OEM 兼容策略

采用 4 级方案：
1. **品牌黑名单**: 跳过已知崩溃的键（如 vivo 的 `nr_sa_mode`）
2. **键名替换**: 小米专用键名替换（如 `nr_sa_mode → nr_mode`）
3. **写入验证**: 华为/荣耀/三星启用 3 次循环验证 + 功能性验证（dumpsys telephony.registry 检查网络制式实际变化）
4. **PNM 受限标记**: 验证失败后标记避免反复尝试

### 4. 运营商默认值修正

| 运营商 | 旧值 | 新值 | 原因 |
|--------|------|------|------|
| 电信 | 26 | 27 | 原 26 不含 CDMA 失语音 |
| 移动 | 23 | 32 | 原 23 NR only 丢失 4G 回退 |
| 广电 | 26 | 33 | 补全 TD-SCDMA/CDMA/EvDo |

### 5. 场景模式隔离

| 模式 | 入口 | 调度器行为 | PNM 操作 |
|------|------|-----------|---------|
| 游戏模式 | 菜单 2 | 严格让位（跳过整轮） | lock_lte (mode=11) + ENDC=0 |
| 代理稳定模式 | 菜单 33 | 严格让位（跳过整轮） | lock_lte (mode=11) + Data Saver |
| 视频/社交/下载模式 | 菜单 1/3/4 | 严格让位 | 无 PNM 操作 |
| 5G 假满格降级 | 自动触发 | 主动执行 | degrade_5g_to_4g (mode=9) |

### 6. 双卡数据采集策略

`network_info.sh` 支持双卡设备（卡1/卡2），通过不同数据源提取：

| 数据项 | 卡1 来源 | 卡2 来源 |
|--------|----------|----------|
| **运营商** | `getprop gsm.sim.operator.alpha` → `cut -d',' -f1`（取逗号分隔第一段） | 同主属性 `cut -d',' -f2`（取第二段），fallback 到 `.2` 后缀属性 |
| **网络制式** | `dumpsys telephony.registry` → `mDataNetworkType` 第一个匹配项 | 同 dumpsys → `sed -n '2p'` 取第二个匹配项 |
| **信号 dBm/Level** | `dumpsys telephony.registry` → `mDbm`/`mLevel` 第一个匹配项 | 同 dumpsys → `sed -n '2p'` 取第二个匹配项 |

**核心原则：** `dumpsys telephony.registry` 中双卡数据按卡1→卡2顺序排列，用 `sed -n '2p'` 取第二个匹配项，无需 awk 块截取。`getprop gsm.sim.operator.alpha` 在双卡设备上返回逗号分隔值（如 "中国移动,中国联通"），用 `cut -d','` 拆分。

**RAT 编号映射：** `_rat_number_to_name()` 将 `mDataNetworkType` 数值转为可读名称（20→5G NR, 13/19→4G LTE, 3/8/9/10/14/15/17→3G, 1/2/16→2G）。

---

## 可维护性指南

### 维护 AGENTS.md（首要规则）

**每次变更代码后，应考虑检查并更新 AGENTS.md 中以下对应部分：**

| 变更类型 | 需更新的 AGENTS.md 章节 |
|---------|----------------------|
| 新增/删除/重命名脚本文件 | 目录结构、调度器架构（如涉及 monitor） |
| 修改函数签名或行为 | 关键架构决策、测试验证要点 |
| 新增/移除品牌支持 | 项目概况（品牌列表）、OEM 兼容策略、可维护性指南（添加新品牌步骤） |
| 新增场景模式 | 场景模式隔离表、可维护性指南（添加新场景模式步骤） |
| 修改 WebUI | 代码约定（WebUI 规范）、测试验证要点 |
| 修改构建流程 | 项目概况（CI 构建版本）、build.yml |
| 调整版本号策略 | 项目概况（当前版本描述） |

判断标准：**如果有人在阅读 AGENTS.md 后会对代码产生错误预期，那就说明需要更新了。**

### 添加新品牌支持

1. 在 `oem_compat.sh` 的 `se_detect_brand()` 中添加识别
2. 在 `se_key_supported()` 中添加键名过滤/替换
3. 在 `se_should_verify_write()` 中添加品牌到验证名单
4. 在 `se_is_brand_supports_pnm()` 中添加品牌支持声明
5. 更新 README.md 的品牌兼容表

### 添加新场景模式

1. 在 `weaknet.sh` 中添加模式函数
2. 在 `action.sh` 的菜单 switch 中添加选项
3. 在 `config.sh` 中添加配置开关
4. 在 `monitor.sh` 的 `is_weaknet_active()` 等效逻辑中添加隔离（检查 `$WEAKNET_ACTIVE_FLAG`）

### 添加新代理白名单管理功能

1. 在 `weaknet.sh` 中添加 `add-wl`/`rm-wl` 命令处理
2. 确保 `validate_package_name()` 和 `validate_uid()` 安全校验
3. 在 `action.sh` 菜单中添加对应入口
4. 在 WebUI 中添加交互卡片