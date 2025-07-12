#!/usr/bin/env bash

# ===========================================================
# 增强版 UFW 防火墙管理工具
# 版本: 6.0
# 项目地址: https://github.com/Lanlan13-14/UFW-Easy
# ===========================================================

GITHUB_REPO="https://github.com/Lanlan13-14/UFW-Easy"
SCRIPT_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/ufw-easy"
UNINSTALL_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/uninstall.sh"
INSTALL_PATH="/usr/local/bin/ufw-easy"

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用 sudo 或以 root 用户运行此脚本"
        exit 1
    fi
}

install_self() {
    echo "🔧 正在安装脚本到系统路径..."
    local script_path
    script_path=$(realpath "$0")
    if [ -f "$INSTALL_PATH" ] && [ "$(realpath "$INSTALL_PATH")" = "$script_path" ]; then
        echo "ℹ️ 脚本已经安装在 $INSTALL_PATH"
        return
    fi
    cp "$script_path" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"
    if [ $? -eq 0 ]; then
        echo "✅ 安装成功！您现在可以通过 'sudo ufw-easy' 运行本程序。"
    else
        echo "❌ 安装失败，请检查权限。"
        exit 1
    fi
}

install_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo "🔧 安装 UFW 防火墙和必要组件..."
        apt update
        apt install -y ufw iptables-persistent netfilter-persistent
        echo "✅ UFW 和相关组件已安装"
        ufw disable >/dev/null 2>&1
        echo "⚠️ UFW 已禁用（等待手动启用）"
        mkdir -p /etc/iptables
    fi
}

show_menu() {
    clear
    echo "====================================================="
    echo "          UFW 防火墙管理工具 (sudo ufw-easy)"
    echo "  项目地址: ${GITHUB_REPO}"
    echo "====================================================="
    ufw_status=$(ufw status | grep -i status)
    echo " 当前状态: ${ufw_status}"
    echo " 默认入站策略: deny (拒绝所有)"
    echo " 默认出站策略: allow (允许所有)"
    echo " IP转发状态: $(sysctl -n net.ipv4.ip_forward)"
    echo "-----------------------------------------------------"
    echo " 1. 显示防火墙状态和规则"
    echo " 2. 添加简单规则"
    echo " 3. 添加高级规则"
    echo " 4. 删除规则"
    echo " 5. 查看应用配置文件"
    echo " 6. 端口转发设置"
    echo " 7. 重启防火墙并应用规则"
    echo " 8. 禁用防火墙"
    echo " 9. 重置防火墙"
    echo "10. 更新脚本"
    echo "11. 卸载脚本"
    echo " 0. 退出"
    echo "====================================================="
    echo -n "请选择操作 [0-11]: "
}

show_status() {
    clear
    echo "==================== 防火墙状态 ===================="
    ufw status verbose
    echo "---------------------------------------------------"
    echo "==================== 规则列表 ======================"
    ufw status numbered
    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

add_rule() {
    local rule="$1"
    if ! ufw insert 1 $rule; then
        ufw $rule
    fi
    echo "✅ 规则已添加: $rule"
    echo "⚠️ 注意: 规则将在重载防火墙后生效"
}

show_protocol_menu() {
    local port="$1"
    local rule_type="$2"
    local ip="$3"

    while true; do
        clear
        echo "==================== 协议选择 ===================="
        echo " 端口: $port"
        [ -n "$ip" ] && echo " IP地址: $ip"
        echo "-------------------------------------------------"
        echo " 1. TCP"
        echo " 2. UDP"
        echo " 3. TCP+UDP"
        echo " 0. 返回上一级"
        echo "================================================="
        echo -n "请选择协议 [0-3]: "
        read protocol_choice

        case $protocol_choice in
            1) 
                if [ -z "$ip" ]; then
                    add_rule "$rule_type $port/tcp"
                else
                    add_rule "$rule_type from $ip to any port $port/tcp"
                fi
                read -n 1 -s -r -p "✅ 规则已添加，按任意键继续..."
                return 1
                ;;
            2) 
                if [ -z "$ip" ]; then
                    add_rule "$rule_type $port/udp"
                else
                    add_rule "$rule_type from $ip to any port $port/udp"
                fi
                read -n 1 -s -r -p "✅ 规则已添加，按任意键继续..."
                return 1
                ;;
            3) 
                if [ -z "$ip" ]; then
                    add_rule "$rule_type $port"
                else
                    add_rule "$rule_type from $ip to any port $port"
                fi
                read -n 1 -s -r -p "✅ 规则已添加，按任意键继续..."
                return 1
                ;;
            0) 
                return 0
                ;;
            *) 
                echo "❌ 无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

add_simple_rule() {
    while true; do
        clear
        echo "==================== 添加简单规则 ===================="
        echo " 1. 允许端口 (所有来源)"
        echo " 2. 拒绝端口 (所有来源)"
        echo " 3. 允许来源IP (所有端口)"
        echo " 4. 拒绝来源IP (所有端口)"
        echo " 5. 允许特定IP访问特定端口"
        echo " 0. 返回主菜单"
        echo "-----------------------------------------------------"
        echo -n "请选择操作 [0-5]: "
        read choice

        case $choice in
            1)
                echo -n "请输入要允许的端口 (如: 80, 443, 22): "
                read port
                if [ -n "$port" ]; then
                    show_protocol_menu "$port" "allow"
                else
                    echo "❌ 端口不能为空"
                    sleep 1
                fi
                ;;
            2)
                echo -n "请输入要拒绝的端口 (如: 8080, 21): "
                read port
                if [ -n "$port" ]; then
                    show_protocol_menu "$port" "deny"
                else
                    echo "❌ 端口不能为空"
                    sleep 1
                fi
                ;;
            3)
                echo -n "请输入要允许的IP地址 (如: 192.168.1.100): "
                read ip
                if [ -n "$ip" ]; then
                    add_rule "allow from $ip"
                    echo "✅ 规则已添加: 允许来自 $ip 的所有访问"
                    read -n 1 -s -r -p "按任意键继续..."
                else
                    echo "❌ IP地址不能为空"
                    sleep 1
                fi
                ;;
            4)
                echo -n "请输入要拒绝的IP地址 (如: 10.0.0.5): "
                read ip
                if [ -n "$ip" ]; then
                    add_rule "deny from $ip"
                    echo "✅ 规则已添加: 拒绝来自 $ip 的所有访问"
                    read -n 1 -s -r -p "按任意键继续..."
                else
                    echo "❌ IP地址不能为空"
                    sleep 1
                fi
                ;;
            5)
                echo -n "请输入要允许的IP地址 (如: 192.168.1.100): "
                read ip
                echo -n "请输入要允许的端口 (如: 22): "
                read port
                if [ -n "$ip" ] && [ -n "$port" ]; then
                    show_protocol_menu "$port" "allow" "$ip"
                else
                    echo "❌ IP地址和端口都不能为空"
                    sleep 1
                fi
                ;;
            0) return ;;
            *) 
                echo "❌ 无效选择"
                sleep 1
                ;;
        esac
    done
}

add_advanced_rule() {
    while true; do
        clear
        echo "==================== 添加高级规则 ===================="
        echo " 1. 允许特定IP访问特定端口范围"
        echo " 2. 设置限速规则"
        echo " 3. 允许特定网络接口"
        echo " 4. 设置特定协议规则"
        echo " 5. 添加应用配置文件规则"
        echo " 0. 返回主菜单"
        echo "-----------------------------------------------------"
        echo -n "请选择操作 [0-5]: "
        read choice

        case $choice in
            1)
                echo -n "请输入要允许的IP地址: "
                read ip
                echo -n "请输入起始端口: "
                read start_port
                echo -n "请输入结束端口: "
                read end_port
                if [ -n "$ip" ] && [ -n "$start_port" ] && [ -n "$end_port" ]; then
                    show_protocol_menu "$start_port:$end_port" "allow" "$ip"
                else
                    echo "❌ 所有字段都必须填写"
                    sleep 1
                fi
                ;;
            2)
                echo -n "请输入端口: "
                read port
                if [ -n "$port" ]; then
                    show_protocol_menu "$port" "limit"
                else
                    echo "❌ 端口不能为空"
                    sleep 1
                fi
                ;;
            3)
                echo -n "请输入端口: "
                read port
                echo -n "请输入网络接口 (如: eth0): "
                read interface
                if [ -n "$port" ] && [ -n "$interface" ]; then
                    while true; do
                        clear
                        echo "==================== 协议选择 ===================="
                        echo " 端口: $port"
                        echo " 接口: $interface"
                        echo "-------------------------------------------------"
                        echo " 1. TCP"
                        echo " 2. UDP"
                        echo " 3. TCP+UDP"
                        echo " 0. 返回"
                        echo "================================================="
                        echo -n "请选择协议 [0-3]: "
                        read protocol_choice
                        case $protocol_choice in
                            1)
                                add_rule "allow in on $interface to any port $port/tcp"
                                echo "✅ 规则已添加: 允许 $interface 接口上的 $port/TCP 访问"
                                read -n 1 -s -r -p "按任意键继续..."
                                break
                                ;;
                            2)
                                add_rule "allow in on $interface to any port $port/udp"
                                echo "✅ 规则已添加: 允许 $interface 接口上的 $port/UDP 访问"
                                read -n 1 -s -r -p "按任意键继续..."
                                break
                                ;;
                            3)
                                add_rule "allow in on $interface to any port $port"
                                echo "✅ 规则已添加: 允许 $interface 接口上的 $port 访问"
                                read -n 1 -s -r -p "按任意键继续..."
                                break
                                ;;
                            0) break ;;
                            *) echo "❌ 无效选择"; sleep 1 ;;
                        esac
                    done
                else
                    echo "❌ 所有字段都必须填写"
                    sleep 1
                fi
                ;;
            4)
                echo -n "请输入端口: "
                read port
                echo -n "允许还是拒绝? (allow/deny): "
                read action
                if [ -n "$port" ] && [ -n "$action" ]; then
                    show_protocol_menu "$port" "$action"
                else
                    echo "❌ 所有字段都必须填写"
                    sleep 1
                fi
                ;;
            5)
                echo "可用的应用配置文件:"
                ufw app list
                echo -n "请输入应用配置文件名: "
                read app
                if [ -n "$app" ]; then
                    add_rule "allow $app"
                    echo "✅ 规则已添加: 允许 $app 应用配置文件"
                    read -n 1 -s -r -p "按任意键继续..."
                else
                    echo "❌ 应用配置文件名不能为空"
                    sleep 1
                fi
                ;;
            0) return ;;
            *) echo "❌ 无效选择"; sleep 1 ;;
        esac
    done
}

delete_rule() {
    clear
    echo "===================== 删除规则 ===================="
    echo "当前防火墙规则列表:"
    ufw status numbered
    echo "--------------------------------------------------"
    echo -n "请输入要删除的规则编号 (或 'a' 删除所有规则): "
    read rule_num
    if [ -z "$rule_num" ]; then
        echo "❌ 规则编号不能为空"
    elif [ "$rule_num" = "a" ]; then
        echo -n "⚠️ 确定要删除所有规则吗? [y/N]: "
        read confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            ufw reset --force
            echo "✅ 所有规则已删除"
            echo "⚠️ 注意: 变更将在重载防火墙后生效"
        else
            echo "❌ 操作已取消"
        fi
    else
        cleaned_num=$(echo "$rule_num" | tr -d '[] ' | tr -cd '0-9')
        if [ -z "$cleaned_num" ]; then
            echo "❌ 无效的规则编号: $rule_num"
        elif ufw status numbered | grep -q "^\[ *$cleaned_num\]"; then
            ufw --force delete "$cleaned_num"
            echo "✅ 规则 $cleaned_num 已删除 (输入: $rule_num)"
            echo "⚠️ 注意: 变更将在重载防火墙后生效"
        else
            echo "❌ 规则 $cleaned_num 不存在 (输入: $rule_num)"
        fi
    fi
    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

view_app_profiles() {
    clear
    echo "==================== 应用配置文件 ===================="
    echo "可用配置文件列表:"
    ufw app list
    echo -n "输入配置文件名称查看详情 (直接回车返回): "
    read app
    if [ -n "$app" ]; then
        echo "---------------------------------------------------"
        ufw app info "$app"
    fi
    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

ensure_ip_forwarding() {
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        sysctl -p >/dev/null
        echo "✅ 已开启IP转发并持久化"
    fi
}

check_forwarding_rules() {
    if ! iptables -t nat -L PREROUTING -n | grep -q "DNAT"; then
        sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
        sysctl -p >/dev/null
        echo "ℹ️ 所有端口转发已删除，已关闭IP转发"
    fi
}

port_forwarding() {
    mkdir -p /etc/iptables
    while true; do
        clear
        echo "==================== 端口转发设置 ===================="
        echo " 1. 添加端口转发规则"
        echo " 2. 查看当前端口转发规则"
        echo " 3. 删除端口转发规则"
        echo " 0. 返回主菜单"
        echo "-----------------------------------------------------"
        echo -n "请选择操作 [0-3]: "
        read choice
        case $choice in
            1)
                echo -n "请输入源端口: "
                read src_port
                echo -n "请输入目标IP: "
                read dest_ip
                echo -n "请输入目标端口: "
                read dest_port
                if [ -n "$src_port" ] && [ -n "$dest_ip" ] && [ -n "$dest_port" ]; then
                    ensure_ip_forwarding
                    while true; do
                        clear
                        echo "==================== 协议选择 ===================="
                        echo " 源端口: $src_port"
                        echo " 目标: $dest_ip:$dest_port"
                        echo "-------------------------------------------------"
                        echo " 1. TCP"
                        echo " 2. UDP"
                        echo " 3. TCP+UDP"
                        echo " 0. 返回"
                        echo "================================================="
                        echo -n "请选择协议 [0-3]: "
                        read protocol_choice
                        rule_comment="PortForwarding: ${src_port}->${dest_ip}:${dest_port}"
                        case $protocol_choice in
                            1)
                                protocol="tcp"
                                iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                                iptables -t nat -A POSTROUTING -p tcp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                                ufw allow proto tcp to "$dest_ip" port "$dest_port" comment "$rule_comment (TCP)"
                                ;;
                            2)
                                protocol="udp"
                                iptables -t nat -A PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                                iptables -t nat -A POSTROUTING -p udp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                                ufw allow proto udp to "$dest_ip" port "$dest_port" comment "$rule_comment (UDP)"
                                ;;
                            3)
                                protocol="tcp+udp"
                                iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                                iptables -t nat -A POSTROUTING -p tcp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                                iptables -t nat -A PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                                iptables -t nat -A POSTROUTING -p udp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                                ufw allow proto tcp to "$dest_ip" port "$dest_port" comment "$rule_comment (TCP)"
                                ufw allow proto udp to "$dest_ip" port "$dest_port" comment "$rule_comment (UDP)"
                                ;;
                            0) echo "❌ 操作已取消"; sleep 1; continue 2 ;;
                            *) echo "❌ 无效选择，使用默认值: TCP+UDP"
                               protocol="tcp+udp"
                               iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                               iptables -t nat -A POSTROUTING -p tcp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                               iptables -t nat -A PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                               iptables -t nat -A POSTROUTING -p udp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                               ufw allow proto tcp to "$dest_ip" port "$dest_port" comment "$rule_comment (TCP)"
                               ufw allow proto udp to "$dest_ip" port "$dest_port" comment "$rule_comment (UDP)"
                               ;;
                        esac
                        iptables-save > /etc/iptables/rules.v4
                        echo "✅ 端口转发已添加: ${src_port}(${protocol}) -> ${dest_ip}:${dest_port}"
                        echo "⚠️ 注意: 变更将在重载防火墙后生效"
                        read -n 1 -s -r -p "按任意键继续..."
                        break
                    done
                else
                    echo "❌ 所有字段都必须填写"
                    sleep 1
                fi
                ;;
            2)
                echo "当前NAT端口转发规则(仅显示DNAT):"
                iptables -t nat -L PREROUTING -n --line-numbers | grep "DNAT"
                echo -e "\n当前UFW转发放行规则:"
                ufw status numbered | grep "PortForwarding:"
                if ! iptables -t nat -L PREROUTING -n | grep -q "DNAT"; then
                    echo "ℹ️ 没有活动的端口转发规则"
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3)
                clear
                echo "当前NAT端口转发规则(仅DNAT):"
                dnat_rules=$(iptables -t nat -L PREROUTING -n --line-numbers | grep "DNAT")
                if [ -z "$dnat_rules" ]; then
                    echo "ℹ️ 没有活动的端口转发规则"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                echo "$dnat_rules"
                echo -n "请输入要删除的 DNAT 规则编号: "
                read rule_num
                rule_info=$(echo "$dnat_rules" | grep "^ *$rule_num ")
                if [ -z "$rule_info" ]; then
                    echo "❌ 输入的编号不属于DNAT规则"
                    sleep 1
                    continue
                fi
                dest_info=$(echo "$rule_info" | awk '{for(i=1;i<=NF;i++) if($i=="to:") print $(i+1)}')
                dest_ip=$(echo "$dest_info" | cut -d: -f1)
                dest_port=$(echo "$dest_info" | cut -d: -f2)
                protocol=$(echo "$rule_info" | awk '{print $3}') # tcp/udp
                src_port=$(echo "$rule_info" | awk '{for(i=1;i<=NF;i++) if($i=="dpt:") print $(i+1)}')
                if [ -z "$src_port" ]; then
                    src_port=$(echo "$rule_info" | grep -oP '(--dport|dpt:)[ ]?\K[0-9]+')
                fi
                iptables -t nat -D PREROUTING "$rule_num"
                while true; do
                    post_rule_num=$(iptables -t nat -L POSTROUTING -n --line-numbers | grep "$dest_ip.*$dest_port" | grep "$protocol" | head -n1 | awk '{print $1}')
                    if [ -n "$post_rule_num" ]; then
                        iptables -t nat -D POSTROUTING "$post_rule_num"
                    else
                        break
                    fi
                done
                iptables-save > /etc/iptables/rules.v4
                rule_comment="PortForwarding: ${src_port}->${dest_ip}:${dest_port}"
                for proto in "TCP" "UDP" ""; do
                    while ufw status numbered | grep -q "$rule_comment${proto:+ \($proto\)}"; do
                        rule_line=$(ufw status numbered | grep "$rule_comment${proto:+ \($proto\)}" | head -n1)
                        rule_idx=$(echo "$rule_line" | grep -oP '^\[\s*\K[0-9]+')
                        [ -n "$rule_idx" ] && echo "y" | ufw delete "$rule_idx"
                    done
                done
                echo "✅ 端口转发规则已彻底删除"
                check_forwarding_rules
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0) return ;;
            *) echo "❌ 无效选择"; sleep 1 ;;
        esac
    done
}

enable_firewall() {
    clear
    echo "================= 启用防火墙并应用规则 ================="
    status=$(ufw status | grep -i status | awk '{print $2}')
    if [ "$status" = "active" ]; then
        echo "✅ 防火墙已启用，正在重载规则..."
        ufw reload
        echo "✅ 防火墙规则已重载"
    else
        echo "🔧 正在启用防火墙并应用规则..."
        ufw default deny incoming >/dev/null
        ufw default allow outgoing >/dev/null
        ufw enable
        echo "✅ 防火墙已启用"
    fi
    echo "---------------------------------------------------"
    echo "当前防火墙状态:"
    ufw status verbose
    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

disable_firewall() {
    clear
    echo "===================== 禁用防火墙 ===================="
    status=$(ufw status | grep -i status | awk '{print $2}')
    if [ "$status" = "inactive" ]; then
        echo "⚠️ 防火墙已处于禁用状态"
    else
        echo -n "⚠️ 确定要禁用防火墙吗? [y/N]: "
        read confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            ufw disable
            echo "✅ 防火墙已禁用"
        else
            echo "❌ 操作已取消"
        fi
    fi
    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

reset_firewall() {
    clear
    echo "===================== 重置防火墙 ===================="
    echo -n "⚠️ 确定要重置防火墙吗? 所有规则将被删除! [y/N]: "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        ufw --force reset
        echo "✅ 防火墙已重置"
        echo "⚠️ 注意: 变更将在重载防火墙后生效"
    else
        echo "❌ 操作已取消"
    fi
    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

update_script() {
    clear
    echo "===================== 更新脚本 ===================="
    echo "正在检查更新..."
    BACKUP_FILE="${INSTALL_PATH}.bak-$(date +%Y%m%d%H%M%S)"
    cp "$INSTALL_PATH" "$BACKUP_FILE"
    echo "✅ 当前脚本已备份到: $BACKUP_FILE"
    echo "下载最新版本..."
    wget -q -O "$INSTALL_PATH" "$SCRIPT_URL"
    if [ $? -eq 0 ]; then
        chmod 755 "$INSTALL_PATH"
        echo "✅ 脚本已更新到最新版本"
        echo "⚠️ 请重新运行脚本以使更新生效"
        echo "项目地址: $GITHUB_REPO"
        echo -n "是否立即重新运行脚本? [Y/n]: "
        read restart_choice
        if [ -z "$restart_choice" ] || [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
            echo "🔄 重新运行脚本..."
            exec sudo ufw-easy
        else
            echo "ℹ️ 您可以选择稍后手动运行: sudo ufw-easy"
            exit 0
        fi
    else
        echo "❌ 更新失败，请检查网络连接"
        echo "已恢复备份: $BACKUP_FILE"
        mv "$BACKUP_FILE" "$INSTALL_PATH"
        echo "---------------------------------------------------"
        read -n 1 -s -r -p "按任意键返回主菜单..."
    fi
}

uninstall_script() {
    clear
    echo "===================== 卸载脚本 ===================="
    echo "⚠️ 警告: 此操作将卸载 UFW 防火墙管理工具"
    echo "      也可能会删除 UFW 防火墙本身，取决于你的选择"
    echo "---------------------------------------------------"
    echo -n "确定要卸载吗? [y/N]: "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if [ -f "$INSTALL_PATH" ]; then
            rm -f "$INSTALL_PATH"
            echo "✅ 已删除安装的脚本: $INSTALL_PATH"
        fi
        echo -n "是否要卸载 UFW 防火墙? [y/N]: "
        read uninstall_ufw
        if [ "$uninstall_ufw" = "y" ] || [ "$uninstall_ufw" = "Y" ]; then
            apt remove -y ufw iptables-persistent
            echo "✅ UFW 和相关组件已卸载"
        else
            echo "ℹ️ 保留了 UFW 防火墙"
        fi
        echo "✅ 卸载完成"
        exit 0
    else
        echo "❌ 操作已取消"
        echo "---------------------------------------------------"
        read -n 1 -s -r -p "按任意键返回主菜单..."
    fi
}

main() {
    check_root
    if [ ! -f "$INSTALL_PATH" ]; then
        install_self
    fi
    install_ufw
    while true; do
        show_menu
        read choice
        case $choice in
            1) show_status ;;
            2) add_simple_rule ;;
            3) add_advanced_rule ;;
            4) delete_rule ;;
            5) view_app_profiles ;;
            6) port_forwarding ;;
            7) enable_firewall ;;
            8) disable_firewall ;;
            9) reset_firewall ;;
            10) update_script ;;
            11) uninstall_script ;;
            0) 
                echo -e "\n感谢使用 UFW 防火墙管理工具!"
                echo "下次使用请运行: sudo ufw-easy"
                echo "项目地址: $GITHUB_REPO"
                echo "再见！"
                exit 0
                ;;
            *)
                echo -e "\n❌ 无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

main