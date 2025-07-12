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

# ... 省略原有 show_status、add_rule、show_protocol_menu、add_simple_rule、add_advanced_rule、delete_rule、view_app_profiles、ensure_ip_forwarding、check_forwarding_rules、enable_firewall、disable_firewall、reset_firewall、update_script、uninstall_script 等函数内容（与原版相同） ...
# 只重写端口转发相关部分

# 端口转发设置（修正版）
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
                            0)
                                echo "❌ 操作已取消"
                                sleep 1
                                continue 2
                                ;;
                            *)
                                echo "❌ 无效选择，使用默认值: TCP+UDP"
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
                # 提取目标IP、端口和协议
                dest_info=$(echo "$rule_info" | awk '{for(i=1;i<=NF;i++) if($i=="to:") print $(i+1)}')
                dest_ip=$(echo "$dest_info" | cut -d: -f1)
                dest_port=$(echo "$dest_info" | cut -d: -f2)
                protocol=$(echo "$rule_info" | awk '{print $3}') # tcp/udp
                # 源端口
                src_port=$(echo "$rule_info" | awk '{for(i=1;i<=NF;i++) if($i=="dpt:") print $(i+1)}')
                # 实际上有时会显示 "--dport NNN" 或 "dpt:NNN" 需兼容
                if [ -z "$src_port" ]; then
                    src_port=$(echo "$rule_info" | grep -oP '(--dport|dpt:)[ ]?\K[0-9]+')
                fi
                # 删除 DNAT 规则
                iptables -t nat -D PREROUTING "$rule_num"
                # 删除 POSTROUTING 规则（只删一个，可能有多个时需多轮处理）
                while true; do
                    post_rule_num=$(iptables -t nat -L POSTROUTING -n --line-numbers | grep "$dest_ip.*$dest_port" | grep "$protocol" | head -n1 | awk '{print $1}')
                    if [ -n "$post_rule_num" ]; then
                        iptables -t nat -D POSTROUTING "$post_rule_num"
                    else
                        break
                    fi
                done
                iptables-save > /etc/iptables/rules.v4
                # UFW规则注释
                rule_comment="PortForwarding: ${src_port}->${dest_ip}:${dest_port}"
                # 自动删除所有相关 UFW 规则（TCP/UDP/全部），循环刷新编号
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
            *)
                echo "❌ 无效选择"
                sleep 1
                ;;
        esac
    done
}

# 主函数和脚本结尾与原版一致
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