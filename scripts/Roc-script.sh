#!/bin/bash
# 360V6 IPQ60XX 512M 全功能优化脚本
# 特性：无独立files目录 | 固定IP | 全局中文 | 性能优化 | NSS网络重载修复 | EasyTier
set -e

# ====================== 1. 修改默认管理IP + 主机名 ======================
sed -i 's/OpenWrt/360V6-NSS/g' package/base-files/files/bin/config_generate
# ====================== 3. NSS 网络重载修复（解决修改LuCI设置后WAN/WAN6消失） ======================
# IPQ60XX + NSS 固件在 uci commit 触发 netifd 重载时，
# NSS ECM/DP 驱动可能无法正确恢复接口绑定，导致 WAN/WAN6 消失、下级设备断线。
# 通过创建 network reload 钩子，在网络重载完成后自动重启 NSS 相关服务来恢复。
mkdir -p package/base-files/files/etc/hotplug.d/iface
cat > package/base-files/files/etc/hotplug.d/iface/99-nss-reload <<'EOF'
#!/bin/sh
# 仅在网络配置重载完成时触发（ACTION=reload, INTERFACE=lan）
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "lan" ] && {
    # 等待 netifd 完成所有接口配置
    sleep 3
    # 重启 NSS ECM 以恢复 WAN 数据路径绑定
    if [ -x /etc/init.d/qca-nss-ecm ]; then
        /etc/init.d/qca-nss-ecm restart 2>/dev/null
    fi
    # 重启 NSS WiFi 卸载/重载以恢复无线数据路径
    if [ -x /etc/init.d/qca-nss-drv-wifi ]; then
        /etc/init.d/qca-nss-drv-wifi restart 2>/dev/null
    fi
    # 刷新防火墙规则
    if [ -x /etc/init.d/firewall ]; then
        /etc/init.d/firewall reload 2>/dev/null
    fi
}
EOF
chmod +x package/base-files/files/etc/hotplug.d/iface/99-nss-reload

# ====================== 4. 系统全局性能调优 ======================
cat > package/base-files/files/etc/sysctl.conf <<EOF
vm.swappiness=5
vm.vfs_cache_pressure=30
vm.min_free_kbytes=8192

net.core.netdev_max_backlog=8192
net.core.somaxconn=4096
net.core.rmem_max=16777216
net.core.wmem_max=16777216

net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=20
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_congestion_control=cubic

net.ipv4.ip_forward=1
net.ipv4.tcp_no_metrics_save=1
EOF

# ====================== 5. 基础默认配置：中文、时区、日志 ======================
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-base-setting <<EOF
#!/bin/sh
# 修改默认管理 IP
uci set network.lan.ipaddr='192.168.60.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# 全局中文 + 时区
uci set luci.main.lang=zh-cn
uci commit luci
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].log_size='32'
uci set system.@system[0].conloglevel='1'
uci set system.@system[0].cronloglevel='1'
uci commit system

# dnsmasq 缓存设置
uci set dhcp.@dnsmasq[0].cache-size='4096'
uci commit dhcp

# 防火墙：启用全锥型NAT（Full Cone NAT）
uci set firewall.@defaults[0].fullcone='1'
uci commit firewall

# 关闭冗余日志服务
/etc/init.d/logd stop
/etc/init.d/logd disable
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-base-setting
