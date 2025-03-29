#!/bin/sh
# ImmortalWrt 首次启动配置脚本 /etc/uci-defaults/99-firstboot-init
# 功能：单次执行的旁路由初始化（无PPPoE/无无线）

LOGFILE="/tmp/firstboot.log"
MARKER_FILE="/etc/immortalwrt-firstboot-done"

# ======================
# 1. 执行条件检查
# ======================
[ -f "$MARKER_FILE" ] && {
    echo "系统已初始化，跳过首次启动配置" > $LOGFILE
    exit 0
}

echo "=== ImmortalWrt 首次启动初始化 $(date) ===" > $LOGFILE

# ======================
# 2. 基础网络参数
# ======================
LAN_IP="192.168.1.2"
GATEWAY_IP="192.168.1.1"
NETMASK="255.255.255.0"

# ======================
# 3. 核心网络配置
# ======================
echo ">> 正在配置旁路由网络" >> $LOGFILE

# 获取物理网卡（排除虚拟接口）
PHY_IFACE=$(ls /sys/class/net/ | grep -Ev '^(lo|wlan|mon|eth0.)' | grep -E '^eth|^en' | head -n1)
[ -z "$PHY_IFACE" ] && {
    echo "错误：未找到合适物理网卡！" >> $LOGFILE
    exit 1
}

# 清除现有WAN配置
uci -q delete network.wan
uci -q delete network.wan6

# 配置LAN口
uci batch <<EOF
set network.lan=interface
set network.lan.device="$PHY_IFACE"
set network.lan.proto='static'
set network.lan.ipaddr="$LAN_IP"
set network.lan.netmask="$NETMASK"
set network.lan.gateway="$GATEWAY_IP"
set network.lan.dns="$GATEWAY_IP"
EOF

# ======================
# 4. 彻底禁用无线
# ======================
echo ">> 正在永久禁用无线" >> $LOGFILE
uci batch <<EOF
delete wireless.radio0
delete wireless.radio1
delete wireless.default_radio0
delete wireless.default_radio1
set wireless.@wifi-device[0].disabled='1'
set wireless.@wifi-iface[0].disabled='1'
EOF

# ======================
# 5. 服务精简配置
# ======================
echo ">> 优化服务配置" >> $LOGFILE

# 禁用DHCP服务
uci set dhcp.lan.ignore='1'

# 防火墙全放行（旁路由模式）
uci set firewall.@zone[0].input='ACCEPT'
uci set firewall.@zone[0].output='ACCEPT'
uci set firewall.@zone[0].forward='ACCEPT'

# 开放管理访问
uci delete ttyd.@ttyd[0].interface 2>/dev/null
uci set dropbear.@dropbear[0].Interface=''

# ======================
# 6. 清理残留配置
# ======================
echo ">> 清理无用配置" >> $LOGFILE

# 删除PPPoE残留
uci -q delete network.pppoe
uci -q delete firewall.@redirect[-1]

# 删除无线相关软件包（可选）
opkg list-installed | grep -E 'wpad|hostapd' | awk '{print $1}' | xargs opkg remove --autoremove

# ======================
# 7. 持久化配置
# ======================
echo ">> 提交所有更改" >> $LOGFILE
uci commit

# 创建标记文件防止重复执行
touch $MARKER_FILE
chmod 400 $MARKER_FILE

echo "=== 首次启动配置完成 $(date) ===" >> $LOGFILE

# 生成配置报告
echo "=== 最终网络配置 ===" >> $LOGFILE
uci show network >> $LOGFILE
echo "=== 无线状态 ===" >> $LOGFILE
uci show wireless >> $LOGFILE

exit 0
