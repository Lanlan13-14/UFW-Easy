#!/usr/bin/env bash

# ===========================================================
# 增强版 UFW 防火墙管理工具
# 版本: 5.0
# 项目地址: https://github.com/Lanlan13-14/UFW-Easy
# 特点:
#   - 自动安装 UFW 但不自动启用
#   - 所有规则变更需手动重载才生效
#   - 规则自动优先于默认拒绝策略
#   - 支持更新脚本功能
#   - 支持 TCP/UDP 协议选择
#   - 采用 UFW 官方推荐方式实现端口转发，确保规则持久生效
# ===========================================================

# 项目信息
GITHUB_REPO="https://github.com/Lanlan13-14/UFW-Easy"
SCRIPT_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/ufw_easy.sh"
UNINSTALL_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/uninstall.sh"

# UFW 配置文件路径
UFW_BEFORE_RULES="/etc/ufw/before.rules"
UFW_DEFAULT_CONF="/etc/default/ufw"


# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用 sudo 或以 root 用户运行此脚本"
        exit 1
    fi
}

# 安装 UFW（如果未安装）
install_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo "🔧 安装 UFW 防火墙..."
        apt update
        apt install -y ufw
        echo "✅ UFW 已安装"
        # 初始禁用 UFW
        ufw disable >/dev/null 2>&1
        echo "⚠️ UFW 已禁用（等待手动启用）"
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo "====================================================="
    echo "          增强版 UFW 防火墙管理工具 (修复版)"
    echo "  项目地址: ${GITHUB_REPO}"
    echo "====================================================="
    ufw_status=$(ufw status | grep -i status)
    echo " 当前状态: ${ufw_status}"
    echo " 默认入站策略: deny (拒绝所有)"
    echo " 默认出站策略: allow (允许所有)"
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

# 显示防火墙状态和规则
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

# 添加规则（确保规则优先于默认拒绝策略）
add_rule() {
    local rule="$1"
    # 使用 insert 1 确保规则在默认策略之前
    if ! ufw insert 1 $rule; then
        # 如果插入失败（可能因为第一条规则已存在），则追加规则
        ufw $rule
    fi
    echo "✅ 规则已添加: $rule"
    echo "⚠️ 注意: 规则将在重载防火墙后生效 (选项 7)"
}

# 协议选择菜单
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

# 添加简单规则
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
            1) # 允许端口
                echo -n "请输入要允许的端口 (如: 80, 443, 22): "
                read port
                if [ -n "$port" ]; then
                    show_protocol_menu "$port" "allow"
                else
                    echo "❌ 端口不能为空"
                    sleep 1
                fi
                ;;
            2) # 拒绝端口
                echo -n "请输入要拒绝的端口 (如: 8080, 21): "
                read port
                if [ -n "$port" ]; then
                    show_protocol_menu "$port" "deny"
                else
                    echo "❌ 端口不能为空"
                    sleep 1
                fi
                ;;
            3) # 允许来源IP
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
            4) # 拒绝来源IP
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
            5) # 允许特定IP访问特定端口
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

# 添加高级规则
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
            1) # 允许特定IP访问特定端口范围
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
            2) # 设置限速规则
                echo -n "请输入端口: "
                read port
                if [ -n "$port" ]; then
                    show_protocol_menu "$port" "limit"
                else
                    echo "❌ 端口不能为空"
                    sleep 1
                fi
                ;;
            3) # 允许特定网络接口
                echo -n "请输入端口: "
                read port
                echo -n "请输入网络接口 (如: eth0): "
                read interface

                if [ -n "$port" ] && [ -n "$interface" ]; then
                    # 复用协议选择菜单
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
                            0)
                                break
                                ;;
                            *)
                                echo "❌ 无效选择"
                                sleep 1
                                ;;
                        esac
                    done
                else
                    echo "❌ 所有字段都必须填写"
                    sleep 1
                fi
                ;;
            4) # 设置特定协议规则
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
            5) # 添加应用配置文件规则
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
            *)
                echo "❌ 无效选择"
                sleep 1
                ;;
        esac
    done
}

# 删除规则（智能识别输入格式）
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
            ufw --force reset
            echo "✅ 所有规则已删除"
            echo "⚠️ 注意: 变更将在重载防火墙后生效"
        else
            echo "❌ 操作已取消"
        fi
    else
        # 智能识别不同格式的规则编号
        # 处理 [1]、[ 1] 或 1 等格式
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

# 查看应用配置文件
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

# ===================================================================
# ==================== 端口转发功能 (重写/修复) =====================
# ===================================================================

# 准备 UFW 环境以进行端口转发
prepare_ufw_for_forwarding() {
    local changed=0
    # 1. 在 /etc/default/ufw 中设置默认转发策略为 ACCEPT
    if ! grep -q '^DEFAULT_FORWARD_POLICY="ACCEPT"' "$UFW_DEFAULT_CONF"; then
        echo "🔧 正在配置 UFW 转发策略..."
        sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEFAULT_CONF"
        echo "✅ UFW 默认转发策略已设置为 ACCEPT"
        changed=1
    fi

    # 2. 启用内核 IP 转发
    if [[ $(sysctl -n net.ipv4.ip_forward) -ne 1 ]]; then
        echo "🔧 正在启用内核 IP 转发..."
        # 临时生效
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        # 持久化
        if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        fi
        echo "✅ 内核 IP 转发已启用并持久化"
        changed=1
    fi

    # 3. 在 before.rules 中确保 *nat 表存在
    if ! grep -q '^*nat' "$UFW_BEFORE_RULES"; then
        echo "🔧 正在向 before.rules 添加 NAT 表定义..."
        # 在文件顶部添加 *nat 表的基本结构
        sed -i '1s;^;*nat\n:PREROUTING ACCEPT [0:0]\n:POSTROUTING ACCEPT [0:0]\n\n# UFW-EASY-FORWARD-RULES-START\n# UFW-EASY-FORWARD-RULES-END\n\nCOMMIT\n\n;' "$UFW_BEFORE_RULES"
        echo "✅ NAT 表已添加"
        changed=1
    fi
    
    # 4. 如果有任何变动，提示用户
    if [ "$changed" -eq 1 ]; then
        echo "⚠️ 端口转发环境已配置。建议重启防火墙 (选项 7) 以确保所有设置生效。"
        sleep 2
    fi
}

# 添加端口转发规则
add_forwarding_rule() {
    clear
    echo "================== 添加端口转发规则 =================="
    prepare_ufw_for_forwarding

    echo -n "请输入源端口 (外部访问的端口): "
    read src_port
    echo -n "请输入目标IP (要转发到的内网IP): "
    read dest_ip
    echo -n "请输入目标端口 (目标IP上的服务端口): "
    read dest_port

    if [ -z "$src_port" ] || [ -z "$dest_ip" ] || [ -z "$dest_port" ]; then
        echo "❌ 所有字段都必须填写。"
        sleep 2
        return
    fi
    
    # 协议选择
    echo -n "请选择协议 (1.TCP, 2.UDP, 3.TCP+UDP) [3]: "
    read proto_choice
    
    local protocols=()
    case $proto_choice in
        1) protocols+=("tcp") ;;
        2) protocols+=("udp") ;;
        *) protocols+=("tcp" "udp") ;;
    esac

    local rules_added=0
    for proto in "${protocols[@]}"; do
        # 为每条规则创建唯一的注释，便于管理
        local rule_comment="# UFW-EASY-FORWARD: ${src_port}/${proto} -> ${dest_ip}:${dest_port}"
        
        # 检查规则是否已存在
        if grep -qF "$rule_comment" "$UFW_BEFORE_RULES"; then
            echo "ℹ️ 规则: ${rule_comment} 已存在，跳过。"
            continue
        fi

        # 定义 PREROUTING (DNAT) 和 POSTROUTING (MASQUERADE) 规则
        local prerouting_rule="-A PREROUTING -p ${proto} --dport ${src_port} -j DNAT --to-destination ${dest_ip}:${dest_port}"
        local postrouting_rule="-A POSTROUTING -s ${dest_ip}/32 -d ${dest_ip}/32 -p ${proto} --dport ${dest_port} -j MASQUERADE"
        
        # 将规则插入到 # UFW-EASY-FORWARD-RULES-END 标记之前
        sed -i "/# UFW-EASY-FORWARD-RULES-END/i ${rule_comment}\n${prerouting_rule}\n${postrouting_rule}\n" "$UFW_BEFORE_RULES"
        
        echo "✅ 规则已添加: ${rule_comment}"
        rules_added=1
    done

    if [ "$rules_added" -eq 1 ]; then
        echo "✅ 端口转发规则已成功写入 ${UFW_BEFORE_RULES}"
        echo "⚠️ 请使用菜单选项 7 重启防火墙以应用新规则！"
    fi
    
    read -n 1 -s -r -p "按任意键返回..."
}

# 查看端口转发规则
view_forwarding_rules() {
    clear
    echo "========== 查看端口转发规则 =========="
    echo "--- (A) 已配置的规则 (${UFW_BEFORE_RULES}) ---"
    # 使用 awk 来美化输出
    grep '# UFW-EASY-FORWARD:' "$UFW_BEFORE_RULES" | awk '{print "  " $0}' || echo "  未找到已配置的转发规则。"
    echo "---------------------------------------------------"
    echo "--- (B) 当前活动的 NAT 规则 (通过 iptables 查看) ---"
    (iptables -t nat -L PREROUTING -n -v | grep 'DNAT' | awk '{print "  [PREROUTING] " $0}') || echo "  未找到活动的 PREROUTING 规则。"
    (iptables -t nat -L POSTROUTING -n -v | grep 'MASQUERADE' | awk '{print "  [POSTROUTING] " $0}') || echo "  未找到活动的 POSTROUTING 规则。"
    echo "---------------------------------------------------"
    echo "说明: (A) 是您已保存的配置，将在下次重载后生效。"
    echo "      (B) 是当前正在运行的规则。两者可能不同步，直到您重载防火墙。"
    read -n 1 -s -r -p "按任意键返回..."
}

# 删除端口转发规则
delete_forwarding_rule() {
    clear
    echo "================== 删除端口转发规则 =================="
    
    # 从 before.rules 文件中读取并编号规则
    mapfile -t rules < <(grep '# UFW-EASY-FORWARD:' "$UFW_BEFORE_RULES")
    
    if [ ${#rules[@]} -eq 0 ]; then
        echo "ℹ️ 在 ${UFW_BEFORE_RULES} 中未找到可删除的转发规则。"
        sleep 2
        return
    fi
    
    echo "请选择要从配置文件中删除的转发规则:"
    for i in "${!rules[@]}"; do
        echo " $((i+1))) ${rules[$i]}"
    done
    echo " 0) 取消"
    echo "---------------------------------------------------"
    echo -n "请输入编号: "
    read choice

    # 验证输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -le 0 ] || [ "$choice" -gt ${#rules[@]} ]; then
        echo "❌ 无效选择或操作已取消。"
        sleep 2
        return
    fi

    local selected_rule_comment="${rules[$((choice-1))]}"
    
    # 使用 sed 通过唯一的注释来删除规则块 (注释行 + 下面2行规则)
    # 使用特殊的分隔符 `\;` 来避免和规则中的斜杠冲突
    sed -i "\;${selected_rule_comment};{N;N;d;}" "$UFW_BEFORE_RULES"
    
    # 删除可能存在的空行
    sed -i '/^$/N;/^\n$/D' "$UFW_BEFORE_RULES"

    echo "✅ 规则 '${selected_rule_comment}' 已从配置文件中删除。"
    echo "⚠️ 请使用菜单选项 7 重启防火墙以使变更生效！"
    read -n 1 -s -r -p "按任意键返回..."
}

# 端口转发主菜单
port_forwarding() {
    while true; do
        clear
        echo "================ 端口转发设置 (已修复) ================"
        echo " 1. 添加端口转发规则"
        echo " 2. 查看端口转发规则"
        echo " 3. 删除端口转发规则"
        echo " 0. 返回主菜单"
        echo "-----------------------------------------------------"
        echo "说明: 此功能通过修改 UFW 配置文件实现，稳定可靠。"
        echo "      所有变更都需要通过选项 7 重启防火墙才能生效。"
        echo "-----------------------------------------------------"
        echo -n "请选择操作 [0-3]: "
        read choice

        case $choice in
            1) add_forwarding_rule ;;
            2) view_forwarding_rules ;;
            3) delete_forwarding_rule ;;
            0) return ;;
            *)
                echo "❌ 无效选择"
                sleep 1
                ;;
        esac
    done
}

# ===================================================================
# ====================== 原有脚本功能 (未改动) ======================
# ===================================================================

# 启用防火墙并应用规则
enable_firewall() {
    clear
    echo "================= 启用/重载防火墙并应用规则 ================="

    status=$(ufw status | grep -i status | awk '{print $2}')

    if [ "$status" = "active" ]; then
        echo "✅ 防火墙已启用，正在重载所有规则 (包括转发规则)..."
        ufw reload
        echo "✅ 防火墙规则已成功重载"
    else
        echo "🔧 正在启用防火墙并应用所有规则..."
        # 设置默认策略
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

# 禁用防火墙
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

# 重置防火墙
reset_firewall() {
    clear
    echo "===================== 重置防火墙 ===================="
    echo -n "⚠️ 确定要重置防火墙吗? 所有规则 (包括转发规则) 都将被删除! [y/N]: "
    read confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        ufw --force reset
        echo "✅ 防火墙已重置"
        echo "⚠️ 注意: 防火墙现在处于禁用状态，所有配置已清除。"
    else
        echo "❌ 操作已取消"
    fi

    echo "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 更新脚本
update_script() {
    clear
    echo "===================== 更新脚本 ===================="
    echo "正在检查更新..."

    # 获取当前脚本路径
    CURRENT_SCRIPT=$(readlink -f "$0")

    # 备份当前脚本
    BACKUP_FILE="${CURRENT_SCRIPT}.bak-$(date +%Y%m%d%H%M%S)"
    cp "$CURRENT_SCRIPT" "$BACKUP_FILE"
    echo "✅ 当前脚本已备份到: $BACKUP_FILE"

    # 下载最新版本
    echo "下载最新版本..."
    if ! wget -q -O "$CURRENT_SCRIPT" "$SCRIPT_URL"; then
        echo "❌ 更新失败，请检查网络连接或 GitHub 访问"
        echo "已恢复备份: $BACKUP_FILE"
        mv "$BACKUP_FILE" "$CURRENT_SCRIPT"
        echo "---------------------------------------------------"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return
    fi
    
    # 设置执行权限
    chmod +x "$CURRENT_SCRIPT"
    echo "✅ 脚本已更新到最新版本"
    echo "⚠️ 请重新运行脚本以使更新生效"
    echo "项目地址: $GITHUB_REPO"

    # 询问是否重新运行
    echo -n "是否立即重新运行脚本? [Y/n]: "
    read restart_choice

    if [ -z "$restart_choice" ] || [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
        echo "🔄 重新运行脚本..."
        exec "$CURRENT_SCRIPT"
    else
        echo "ℹ️ 您可以选择稍后手动运行: sudo $CURRENT_SCRIPT"
        exit 0
    fi
}


# 卸载脚本
uninstall_script() {
    clear
    echo "===================== 卸载脚本 ===================="
    echo "⚠️ 警告: 此操作将卸载 UFW 防火墙管理工具"
    echo "         也可能会删除 UFW 防火墙本身，取决于你的选择"
    echo "---------------------------------------------------"
    echo -n "确定要卸载吗? [y/N]: "
    read confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "正在执行卸载脚本..."
        # 执行远程卸载脚本
        if command -v curl &>/dev/null; then
            bash -c "$(curl -sL $UNINSTALL_URL)"
        elif command -v wget &>/dev/null; then
            bash -c "$(wget -qO- $UNINSTALL_URL)"
        else
            echo "❌ 无法下载卸载脚本，请安装 curl 或 wget。"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        exit 0
    else
        echo "❌ 操作已取消"
        echo "---------------------------------------------------"
        read -n 1 -s -r -p "按任意键返回主菜单..."
    fi
}

# 主函数
main() {
    check_root
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

# 启动主函数
main
