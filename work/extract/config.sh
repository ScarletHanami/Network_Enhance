#!/system/bin/sh
# config.sh — 卫星地球 Pro v6.3.0 用户配置中心

# ===============================
# 1. 运营商
# ===============================
CARRIER="auto"

# ===============================
# 2. WiFi 优化
# ===============================
ENABLE_WIFI_OPTIMIZE=true
WIFI_BAD_RSSI=88
WIFI_IDLE_MS=7200000

# ===============================
# 3. 移动网络优化
# ===============================
ENABLE_MOBILE_OPTIMIZE=true
ENABLE_5G_SA=true

# ===============================
# 4. DNS 预热
# ===============================
ENABLE_DNS_PREFETCH=true

# ===============================
# 5. Private DNS (DoT)
# ===============================
ENABLE_PRIVATE_DNS=false
PRIVATE_DNS_HOST="dns.alidns.com"

# ===============================
# 6. late_start 阶段验证
# ===============================
ENABLE_LATE_VERIFY=true

# ===============================
# 7. 智能调度器
# ===============================
ENABLE_MONITOR=true
ENABLE_SWITCH_NOTIFY=true
ENABLE_DYNAMIC_PARAMS=true
ENABLE_PING_FEEDBACK=true

# v6.2.0+: OEM 兼容性总开关
ENABLE_OEM_COMPAT=true

# 信号阈值
WIFI_STRONG_RSSI=60
WIFI_WEAK_RSSI=75
MOBILE_STRONG_DBM=85
MOBILE_WEAK_DBM=105
PING_GOOD_MS=80
PING_BAD_MS=200

# 检测间隔（秒）
MONITOR_MIN_INTERVAL=300
MONITOR_NORMAL_INTERVAL=600
MONITOR_MAX_INTERVAL=900
NETWORK_READY_TIMEOUT=10
