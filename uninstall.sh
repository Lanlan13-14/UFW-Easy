#!/bin/bash

# UFW 防火墙管理工具卸载脚本
# 版本: 3.0
# 特点: 
#   - 卸载后询问是否重启系统
#   - 新增完全删除UFW及所有规则选项

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 sudo 或以 root 用户运行此脚本"
    exit 1
fi

# 显示卸载选项
echo "============================================="
echo "      UFW 防火墙管理工具卸载程序"
echo "============================================="
echo " 1. 仅卸载管理工具 (保留防火墙规则)"
echo " 2. 完全卸载 (删除工具并重置防火墙)"
echo " 3. 完全删除UFW及所有规则 (包括软件包)"
echo " 4. 取消卸载"
echo "============================================="
echo -n "请选择卸载选项 [1-4]: "
read option

case $option in
    1)
        echo "🔧 正在仅卸载管理工具..."
        # 删除主程序
        rm -f /usr/local/bin/ufw-easy

        # 删除配置文件
        rm -f /etc/ufw-easy.conf 2>/dev/null

        echo "✅ 管理工具已卸载"
        echo "ℹ️ 防火墙规则和UFW程序仍然保留"
        ;;
    2)
        echo "⚠️ 正在完全卸载工具并重置防火墙..."
        # 删除主程序
        rm -f /usr/local/bin/ufw-easy

        # 删除配置文件
        rm -f /etc/ufw-easy.conf 2>/dev/null

        # 重置防火墙
        ufw --force reset
        ufw disable

        # 删除端口转发规则
        iptables -t nat -F
        iptables -t mangle -F
        iptables -F
        iptables -X
        
        # 保存空规则
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
        fi

        echo "✅ 工具已完全卸载，防火墙已重置"
        echo "ℹ️ UFW软件包仍然保留在系统中"
        ;;
    3)
        echo "⚠️ 正在完全删除UFW及所有规则..."
        # 删除主程序
        rm -f /usr/local/bin/ufw-easy

        # 删除配置文件
        rm -f /etc/ufw-easy.conf 2>/dev/null

        # 重置防火墙
        ufw --force reset
        ufw disable

        # 删除端口转发规则
        iptables -t nat -F
        iptables -t mangle -F
        iptables -F
        iptables -X
        
        # 保存空规则
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
        fi
        
        # 卸载UFW软件包
        if command -v ufw &> /dev/null; then
            apt-get remove --purge -y ufw
            apt-get autoremove -y
            echo "✅ UFW软件包已完全卸载"
        else
            echo "ℹ️ UFW软件包未安装，无需卸载"
        fi
        
        echo "✅ UFW及所有相关规则已完全删除"
        ;;
    4)
        echo "❌ 卸载已取消"
        exit 0
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac

echo "============================================="
echo "卸载完成！建议重启系统使所有更改生效"

# 询问是否重启系统
echo -n "是否立即重启系统? [y/N]: "
read reboot_choice

if [ "$reboot_choice" = "y" ] || [ "$reboot_choice" = "Y" ]; then
    echo "🔄 正在重启系统..."
    reboot
else
    echo "ℹ️ 您可以选择稍后手动重启: sudo reboot"
    echo "防火墙更改将在重启后完全生效"
fi