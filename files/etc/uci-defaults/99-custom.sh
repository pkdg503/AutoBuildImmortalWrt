#!/bin/sh
# 99-custom.sh - 单网口旁路由专用配置

LOGFILE="/tmp/uci-defaults-log.txt"
echo "=== 新一轮配置开始 $(date) ===" >> $LOGFILE

# 全局配置开关
enable_ipv6="yes"
lan_ipaddr="192.168.1.2"
gateway_ip="192.168.1.1"

# IP格式验证函数
validate_ip() {
  local ip=$1
  if ! echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    echo "错误：IP地址格式无效: $ip" >> $LOGFILE
    exit 1
  fi
}
validate_ip "$lan_ipaddr"
validate_ip "$gateway_ip"

# 物理网卡检测（兼容更多命名规则）
phy_ifname=$(ls /sys/class/net/ | grep -E '^(eth|en[ops]|ens|eno)[0-9]+' | head -n1)
[ -z "$phy_ifname" ] && {
  echo "错误：未找到物理网卡！" >> $LOGFILE
  exit 1
}

# ... [其他配置部分应用上述修正] ...

# 示例：安全的防火墙配置
lan_zone=$(uci show firewall | grep "@zone.*name='lan'" | cut -d'[' -f2 | cut -d']' -f1)
uci set "firewall.@zone[$lan_zone].input='ACCEPT'"

# 提交前验证
if ! uci changes; then
  echo "无配置变更需要提交" >> $LOGFILE
elif ! uci commit; then
  echo "错误：配置提交失败！" >> $LOGFILE
  exit 1
fi

echo "=== 配置成功完成 $(date) ===" >> $LOGFILE
exit 0
