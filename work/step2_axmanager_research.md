# 第二步：AxManager 联网研究摘要

## 来源
- 官方文档：https://fahrez182.github.io/AxManager/plugin/what-is-plugin.html
- GitHub：https://github.com/fahrez182/AxManager
- 用户手册：https://fahrez182.github.io/AxManager/zh/guide/user-manual.html
- 知乎专栏：https://zhuanlan.zhihu.com/p/2011811317716103775
- 多个 YouTube/XDA/Reddit 技术帖

## 1. AxManager 是什么

AxManager（Axeron Manager）是 fahrez182 开发的 Android 应用，本质是：
- **基于 ADB 权限的脚本执行器 + 插件容器**
- 类似 Shizuku 的加强版，通过无线调试（Android 11+）或 USB ADB（Android 10-）拿到 shell 权限
- 兼容 Root 设备（可选启用 Root 模式获得更高权限）
- 提供 Magisk 风格的模块管理 UI，但模块本身运行在 ADB shell 用户权限下
- 核心原理："用无线调试拿到 ADB 权限，再用一个看起来像管理器的 UI 去执行那些 Shell 命令"
- 来源：知乎专栏 + 官方文档

## 2. 模块开发规范（关键）

### 2.1 标准目录结构
```
/data/user_de/0/com.android.shell/axeron/plugins/<MODID>/
├── module.prop          # 必需，模块元数据
├── system/bin/          # 可加入 PATH（仅影响 /system/bin）
├── disable / remove     # 状态标志文件
├── post-fs-data.sh      # BOOT_COMPLETED first sync 阶段
├── service.sh           # BOOT_COMPLETED late_start service 阶段
├── uninstall.sh         # 卸载时执行
├── action.sh            # 用户点击 Action 按钮时执行
├── system.prop          # ⚠️ debug only，通过 setprop 加载
├── customize.sh         # 安装期脚本（被 source）
├── webroot/index.html   # WebUI 界面（KernelSU 兼容 API）
└── 其他任意文件/文件夹
```

### 2.2 module.prop 字段规范（官方原文）
```
id=<string>            # 必须匹配 ^[a-zA-Z][a-zA-Z0-9._-]+$
name=<string>
version=<string>
versionCode=<int>      # 必须是整数
author=<string>
description=<string>
axeronPlugin=<int>     # ⚠️ 用于声明目标 AxManager server 版本
```
**关键约束**：
- `axeronPlugin=N` 必须满足 N ≤ 当前 AxManager server 版本，否则无法刷入
- 模块中 `axeronPlugin=10000` 对应 AxManager 1.0.x（合理）
- 行尾必须是 Unix LF（不能是 CR+LF 或 CR）

### 2.3 生命周期脚本执行时机
- AxManager 使用 **BOOT_COMPLETED 广播 + Hot Restart System** 触发（**不是 init 阶段**）
- 这与 Magisk/KernelSU 的 post-fs-data 阶段（init 时执行）**完全不同**
- 实际执行时机：开机完成后 + AxManager 应用启动时
- **关键含义**：模块脚本的生效时机比 Root 方案晚，系统服务已起来，但用户可能已经解锁屏幕

### 2.4 模块与 AxManager 的交互方式
- **WebUI**：通过 `webroot/index.html`，AxManager 兼容 KernelSU WebUI API
- **JS 桥接**：`Axeron.exec(cmd, args_json)` 同步执行 shell 命令
- **CLI**：通过 action.sh 在用户点击时执行
- **环境变量**：
  - `AXERON=true` 标识在 AxManager 环境
  - `AXERONVER` AxManager 版本
  - `AXERONDIR` AxManager 数据目录
- **BusyBox**：AxManager 自带 Magisk 编译的 BusyBox，在 ash shell 中启用 "Standalone Mode"，所有命令直接调用 BusyBox applet，跨 Android 版本行为一致

### 2.5 官方对 MODDIR 的建议
> "In all scripts of your module, please use `MODDIR=${0%/*}` to get your module's base directory path EXCEPT customize.sh; do NOT hardcode your module path in scripts."

⚠️ **但实测在 action.sh 中**：AxManager 执行 `cd "<pluginPath>"; sh ./action.sh`，导致 `$0="./action.sh"`，`${0%/*}="."`，一旦脚本内部再 `cd` 就失效。**这是原模块 v6.3.0 修复的核心问题，新版本必须保留 pwd 兜底机制**。

## 3. AxManager 免 Root 边界（关键！）

### 3.1 可用（ADB shell 用户权限，uid 2000）
| 类别 | 命令 |
|---|---|
| 系统设置 | `settings put/get/delete global/secure/system <key> <value>` |
| 系统服务 | `cmd <service> <subcommand>`（如 cmd wifi, cmd phone, cmd netpolicy, cmd connectivity, cmd notification） |
| 状态查询 | `dumpsys <service>`（connectivity/wifi/telephony.registry/netstats/policy 等） |
| 属性读取 | `getprop <name>` |
| 网络测试 | `ping`, `nc`, `ip route`, `ifconfig` |
| 进程管理 | `nohup`, `kill`（仅限自己 fork 的子进程） |
| 文件读写 | `/data/local/tmp/`、`/sdcard/`、模块自身目录 |
| 通知 | `cmd notification post/cancel` |
| Activity | `am start/broadcast` |
| Package | `pm list/grant/disable`（部分操作需系统签名） |

### 3.2 不可用（需要 Root 或系统权限）
| 类别 | 命令/操作 | 原因 |
|---|---|---|
| Root 提权 | `su`、`magisk --sqlite` | 需要 root 用户 |
| 内核参数 | `setprop persist.*` 写入 | persist.* 需要 system/root 权限，shell 用户只能读 |
| 系统分区写入 | `/system/`, `/vendor/`, `/product/` 挂载为只读 | mount 操作需要 root |
| `/proc/sys/*` 写入 | `echo X > /proc/sys/net/ipv4/tcp_*` | 需要 root |
| `service call` 直接调用 | 部分需 system uid | 大部分 phone service 调用会因权限被拒 |
| Magisk 模块目录 | `/data/adb/modules/` | 需要 root |

### 3.3 关于 system.prop
官方原文："**system.prop will be loaded as system properties by setprop (debug only)**"

**结论**：
- system.prop 通过 `setprop` 命令加载
- `setprop` 在 shell 用户下**只能修改非 persist.* 的属性**，且部分需要 system 权限
- 原模块 system.prop 写的 `persist.sys.satellite_earth.version=1.0` 和 `persist.sys.satellite_earth.activated=1` 在免Root下**无法生效**
- **解决方案**：移除 system.prop，将其内容迁移到 post-fs-data.sh 中用 `settings put global` 实现

### 3.4 关于 `cmd phone` 子命令
- 官方 `cmd phone` 在 Android 14 上确实存在，但**子命令实现因 OEM 而异**
- AOSP 标准 `cmd phone` 主要是调试命令，**没有公开的 `set-preferred-network-type` 子命令**
- 实际控制网络制式的稳定方法仍是 `settings put global preferred_network_mode <value>`
- `service call phone 108 i32 0 i32 0 i64 "<bitmask>"` 是更底层的方法，但需要从 framework.jar 中提取 TRANSACTION_code，每设备不同，**太脆弱不推荐**

## 4. 兼容性要求与常见坑点

### 4.1 兼容性要求
- 最低 Android 版本：建议 Android 11+（无线调试要求）
- 用户原始要求 Android 14（API 34），合理
- 需要 AxManager 应用已启动（每次重启需重新激活）

### 4.2 常见坑点
1. **路径解析陷阱**：action.sh 中 `$0="./action.sh"`，必须用 pwd 或 AXERONDIR 兜底
2. **system.prop 不生效**：免Root下 setprop persist.* 失败
3. **BOOT_COMPLETED 时机**：模块脚本在用户可能已解锁屏幕后执行，不能假设是开机首刻
4. **`settings put` 写入需 BOOT_COMPLETED**：post-fs-data 阶段某些 settings 可能还未初始化
5. **各 OEM 的 settings key 不一致**：必须做 OEM 兼容性矩阵
6. **WebUI exec 异步返回**：部分 ROM 的 Axeron.exec 返回字符串 errno 而非数字，需双重判断
7. **BusyBox Standalone Mode**：所有命令默认走 BusyBox applet，如需调用系统原版要用全路径

## 5. 与原模块的一致性核对

| 项 | 原模块 | 官方规范 | 评价 |
|---|---|---|---|
| 目录结构 | ✅ 完整 | 符合 | OK |
| module.prop 字段 | ✅ 全部存在 | 符合 | OK |
| axeronPlugin=10000 | 10000 | ≤ server 版本 | OK（对应 1.0.x） |
| MODDIR 路径解析 | pwd + AXERONDIR + MODPATH + $0 + readlink + 硬编码 | 推荐 ${0%/*} | ✅ 原模块增强更稳健 |
| system.prop | persist.sys.satellite_earth.* | debug only | ❌ 免Root不生效 |
| WebUI | Axeron.exec 桥接 | KernelSU 兼容 | ✅ 符合 |
| customize.sh | 存在但被自检误报缺失 | source 调用 | ⚠️ 需修复自检逻辑 |
| OEM 兼容性 | 6 厂商矩阵 | 必须 | ✅ 但需扩展 |

