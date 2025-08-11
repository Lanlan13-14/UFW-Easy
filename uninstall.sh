#!/bin/bash

# 防火墙管理工具卸载脚本
# 版本: 4.0
# 特点:
#   - 卸载后询问是否重启系统
#   - 新增完全删除防火墙及所有规则选项
#   - 卸载时自动停用并删除 portforward systemd 服务
#   - 新增Jool NAT64卸载支持

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ 请使用 sudo 或以 root 用户运行此脚本${NC}"
    exit 1
fi

# 停用并删除 portforward systemd 服务（如果存在）
remove_portforward_service() {
    if [ -f /etc/systemd/system/portforward.service ]; then
        echo -e "${YELLOW}🛠 停用并删除 portforward systemd 服务...${NC}"
        systemctl stop portforward.service >/dev/null 2>&1
        systemctl disable portforward.service >/dev/null 2>&1
        rm -f /etc/systemd/system/portforward.service
        rm -f /etc/portforward_rules.sh
        systemctl daemon-reload
        echo -e "${GREEN}✅ portforward systemd 服务已删除${NC}"
    fi
}

# 卸载Jool NAT64
remove_jool() {
    if lsmod | grep -q jool; then
        echo -e "${YELLOW}🛠 正在卸载Jool NAT64...${NC}"
        
        # 删除Jool实例和配置
        if command -v jool >/dev/null 2>&1; then
            jool instance remove default >/dev/null 2>&1
        fi
        
        # 卸载模块
        modprobe -r jool 2>/dev/null
        
        # 删除持久化配置
        rm -f /etc/modules-load.d/jool.conf
        rm -f /etc/jool.conf
        
        # 删除软件包
        if command -v apt >/dev/null 2>&1; then
            apt-get remove --purge -y jool-tools 2>/dev/null
        fi
        
        echo -e "${GREEN}✅ Jool NAT64已卸载${NC}"
    fi
}

# 清理iptables规则
clean_iptables() {
    echo -e "${YELLOW}🧹 正在清理iptables规则...${NC}"
    
    # 清理IPv4规则
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    
    # 清理IPv6规则
    ip6tables -t nat -F
    ip6tables -t mangle -F
    ip6tables -F
    ip6tables -X
    
    # 保存规则（如果存在iptables持久化）
    if [ -d "/etc/iptables" ]; then
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
    fi
    
    echo -e "${GREEN}✅ iptables规则已清理${NC}"
}

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}      防火墙管理工具卸载程序${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e " 1. 仅卸载管理工具 (保留防火墙规则)"
echo -e " 2. 完全卸载 (删除工具并重置防火墙)"
echo -e " 3. 完全删除防火墙及所有组件 (包括软件包)"
echo -e " 4. 取消卸载"
echo -e "${GREEN}=============================================${NC}"
echo -n -e "${YELLOW}请选择卸载选项 [1-4]: ${NC}"
read option

case $option in
    1)
        echo -e "${YELLOW}🔧 正在仅卸载管理工具...${NC}"
        rm -f /usr/local/bin/ufw-easy
        rm -f /etc/ufw-easy.conf 2>/dev/null
        remove_portforward_service
        echo -e "${GREEN}✅ 管理工具已卸载${NC}"
        echo -e "${YELLOW}ℹ️ 防火墙规则和软件包仍然保留${NC}"
        ;;
    2)
        echo -e "${YELLOW}⚠️ 正在完全卸载工具并重置防火墙...${NC}"
        rm -f /usr/local/bin/ufw-easy
        rm -f /etc/ufw-easy.conf 2>/dev/null
        
        # 重置UFW
        if command -v ufw >/dev/null 2>&1; then
            ufw --force reset
            ufw disable
        fi
        
        clean_iptables
        remove_portforward_service
        remove_jool
        
        echo -e "${GREEN}✅ 工具已完全卸载，防火墙已重置${NC}"
        echo -e "${YELLOW}ℹ️ 防火墙软件包仍然保留在系统中${NC}"
        ;;
    3)
        echo -e "${RED}⚠️ 正在完全删除防火墙及所有组件...${NC}"
        rm -f /usr/local/bin/ufw-easy
        rm -f /etc/ufw-easy.conf 2>/dev/null
        
        # 完全卸载UFW
        if command -v ufw >/dev/null 2>&1; then
            ufw --force reset
            ufw disable
            apt-get remove --purge -y ufw 2>/dev/null
            echo -e "${GREEN}✅ UFW软件包已完全卸载${NC}"
        else
            echo -e "${YELLOW}ℹ️ UFW软件包未安装，无需卸载${NC}"
        fi
        
        clean_iptables
        remove_portforward_service
        remove_jool
        
        # 清理依赖
        if command -v apt >/dev/null 2>&1; then
            apt-get autoremove -y 2>/dev/null
        fi
        
        echo -e "${GREEN}✅ 防火墙及所有相关组件已完全删除${NC}"
        ;;
    4)
        echo -e "${YELLOW}❌ 卸载已取消${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ 无效选择${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}卸载完成！建议重启系统使所有更改生效${NC}"

echo -n -e "${YELLOW}是否立即重启系统? [y/N]: ${NC}"
read reboot_choice

if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🔄 正在重启系统...${NC}"
    reboot
else
    echo -e "${YELLOW}ℹ️ 您可以选择稍后手动重启: sudo reboot${NC}"
    echo -e "${YELLOW}防火墙更改将在重启后完全生效${NC}"
fi