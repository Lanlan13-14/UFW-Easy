#!/usr/bin/env bash

# ===========================================================
# 增强版 UFW 防火墙管理工具
# 版本: 6.3
# 项目地址: https://github.com/Lanlan13-14/UFW-Easy
# 特点: 
#   - 可直接通过 sudo ufw-easy 运行
#   - 自动安装到系统路径
#   - 完整的端口转发支持
#   - 自动管理 IP 转发状态
#   - 基于标签的端口转发规则管理系统
# ===========================================================

# 项目信息
GITHUB_REPO="https://github.com/Lanlan13-14/UFW-Easy"
SCRIPT_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/refs/heads/main/ufw_easy.sh"
UNINSTALL_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/uninstall.sh"

# 安装路径
INSTALL_PATH="/usr/local/bin/ufw-easy"

# 端口转发规则存储
PORT_FORWARD_RULES_FILE="/etc/ufw-easy/port_forward.rules"

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用 sudo 或以 root 用户运行此脚本"
        exit 1
    fi
}

# 安装脚本到系统路径
install_self() {
    echo "🔧 正在安装脚本到系统路径..."
    local script_path
    script_path=$(realpath "$0")

    # 如果已经安装且是同一个文件，跳过
    if [ -f "$INSTALL_PATH" ] && [ "$(realpath "$INSTALL_PATH")" = "$script_path" ]; then
        echo "ℹ️ 脚本已经安装在 $INSTALL_PATH"
        return
    fi

    # 复制到系统路径
    cp "$script_path" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"

    if [ $? -eq 0 ]; then
        echo "✅ 安装成功！您现在可以通过 'sudo ufw-easy' 运行本程序。"
    else
        echo "❌ 安装失败，请检查权限。"
        exit 1
    fi
}

# 安装 UFW（如果未安装）
install_ufw() {
    if ! command -v ufw &>/dev/null; then
        echo "🔧 安装 UFW 防火墙和必要组件..."

        # 更新包列表
        apt update

        # 安装 debconf-utils 来处理交互式提示
        apt install -y debconf-utils

        # 配置 iptables-persistent 的 debconf 回答
        echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
        echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

        # 安装 UFW 和相关组件（使用非交互模式）
        DEBIAN_FRONTEND=noninteractive apt install -y ufw iptables-persistent netfilter-persistent

        if ! command -v ufw &>/dev/null; then
            echo "❌ UFW 安装失败，请检查网络或包管理器状态"
            return 1
        fi

        echo "✅ UFW 和相关组件已安装"
        ufw disable >/dev/null 2>&1
        echo "⚠️ UFW 已禁用（等待手动启用）"
    else
        echo "ℹ️ UFW 已安装，跳过安装步骤"
    fi
}

# 显示主菜单
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
    echo "⚠️ 注意: 规则将在重载防火墙后生效"
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
                    # 如果规则添加成功，继续显示简单规则菜单
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
                    # 复用协议选择菜单
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
                    # 复用协议选择菜单
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
                    # 复用协议选择菜单
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
            ufw reset --force
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

# 确保IP转发已开启并持久化
ensure_ip_forwarding() {
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        sysctl -p >/dev/null
        echo "✅ 已开启IP转发并持久化"
    fi
}

# 检查并关闭IP转发（如果没有转发规则）
check_forwarding_rules() {
    # 只检查用户添加的规则，忽略系统规则
    if [ ! -f "$PORT_FORWARD_RULES_FILE" ] || [ ! -s "$PORT_FORWARD_RULES_FILE" ]; then
        # 没有转发规则时关闭IP转发
        sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
        sysctl -p >/dev/null
        echo "ℹ️ 所有端口转发已删除，已关闭IP转发"
    fi
}

# 保存端口转发规则
save_forward_rule() {
    local rule_id="$1"
    local src_port="$2"
    local dest_ip="$3"
    local dest_port="$4"
    local protocol="$5"
    
    # 确保目录存在
    mkdir -p "$(dirname "$PORT_FORWARD_RULES_FILE")"
    
    # 追加规则到文件
    echo "${rule_id}|${src_port}|${dest_ip}|${dest_port}|${protocol}" >> "$PORT_FORWARD_RULES_FILE"
}

# 删除端口转发规则记录
delete_forward_rule() {
    local rule_id="$1"
    
    if [ -f "$PORT_FORWARD_RULES_FILE" ]; then
        # 创建临时文件
        local temp_file
        temp_file="$(mktemp)"
        
        # 过滤掉要删除的规则
        grep -v "^${rule_id}|" "$PORT_FORWARD_RULES_FILE" > "$temp_file"
        
        # 替换原文件
        mv "$temp_file" "$PORT_FORWARD_RULES_FILE"
    fi
}

# 获取所有端口转发规则
get_forward_rules() {
    if [ -f "$PORT_FORWARD_RULES_FILE" ]; then
        cat "$PORT_FORWARD_RULES_FILE"
    else
        echo ""
    fi
}

# 生成唯一的规则ID
generate_rule_id() {
    date +%s%N | sha256sum | head -c 8
}

# 添加端口转发规则
add_port_forward() {
    echo -n "请输入源端口: "
    read src_port
    echo -n "请输入目标IP: "
    read dest_ip
    echo -n "请输入目标端口: "
    read dest_port

    if [ -z "$src_port" ] || [ -z "$dest_ip" ] || [ -z "$dest_port" ]; then
        echo "❌ 所有字段都必须填写"
        return 1
    fi

    # 确保IP转发已开启
    ensure_ip_forwarding

    # 协议选择
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

        case $protocol_choice in
            1) protocol="tcp";;
            2) protocol="udp";;
            3) protocol="both";;
            0) 
                echo "❌ 操作已取消"
                return 1
                ;;
            *) 
                echo "❌ 无效选择，使用默认值: TCP+UDP"
                protocol="both"
                ;;
        esac
        
        # 生成唯一的规则ID
        rule_id=$(generate_rule_id)
        
        # 添加TCP规则（如果选择）
        if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
            # 添加NAT规则
            iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
            iptables -t nat -A POSTROUTING -p tcp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
            
            # 添加UFW规则
            ufw_comment="PortForward-${rule_id}-TCP"
            ufw allow proto tcp to "$dest_ip" port "$dest_port" comment "$ufw_comment"
            
            # 保存规则
            save_forward_rule "$rule_id" "$src_port" "$dest_ip" "$dest_port" "tcp"
        fi
        
        # 添加UDP规则（如果选择）
        if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
            # 添加NAT规则
            iptables -t nat -A PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
            iptables -t nat -A POSTROUTING -p udp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
            
            # 添加UFW规则
            ufw_comment="PortForward-${rule_id}-UDP"
            ufw allow proto udp to "$dest_ip" port "$dest_port" comment "$ufw_comment"
            
            # 保存规则
            save_forward_rule "$rule_id" "$src_port" "$dest_ip" "$dest_port" "udp"
        fi
        
        # 保存iptables规则
        iptables-save > /etc/iptables/rules.v4
        
        echo "✅ 端口转发已添加: ${src_port}(${protocol}) -> ${dest_ip}:${dest_port}"
        echo "⚠️ 注意: 变更将在重载防火墙后生效"
        read -n 1 -s -r -p "按任意键继续..."
        return 0
    done
}

# 显示端口转发规则
show_port_forwards() {
    echo "==================== 端口转发规则 ===================="
    
    if [ ! -f "$PORT_FORWARD_RULES_FILE" ] || [ ! -s "$PORT_FORWARD_RULES_FILE" ]; then
        echo "ℹ️ 没有活动的端口转发规则"
        return
    fi
    
    # 显示规则表头
    printf "%-8s %-10s %-18s %-10s %-8s\n" "ID" "源端口" "目标IP" "目标端口" "协议"
    echo "---------------------------------------------------"
    
    # 按规则ID分组显示
    declare -A rule_groups
    while IFS='|' read -r rule_id src_port dest_ip dest_port protocol; do
        if [ -z "${rule_groups[$rule_id]}" ]; then
            rule_groups[$rule_id]="$src_port|$dest_ip|$dest_port|$protocol"
        else
            # 合并相同规则ID的协议
            existing="${rule_groups[$rule_id]}"
            protocols=$(echo "$existing" | cut -d'|' -f4)
            rule_groups[$rule_id]="$(echo "$existing" | cut -d'|' -f1-3)|${protocols},$protocol"
        fi
    done < <(sort "$PORT_FORWARD_RULES_FILE")
    
    # 显示分组后的规则
    local count=1
    for rule_id in "${!rule_groups[@]}"; do
        IFS='|' read -r src_port dest_ip dest_port protocols <<< "${rule_groups[$rule_id]}"
        printf "%-2d. %-6s %-10s %-18s %-10s %-8s\n" "$count" "$rule_id" "$src_port" "$dest_ip" "$dest_port" "$protocols"
        ((count++))
    done
}

# 删除端口转发规则
delete_port_forward() {
    if [ ! -f "$PORT_FORWARD_RULES_FILE" ] || [ ! -s "$PORT_FORWARD_RULES_FILE" ]; then
        echo "ℹ️ 没有活动的端口转发规则"
        return
    fi
    
    # 显示所有规则
    show_port_forwards
    
    echo "---------------------------------------------------"
    echo -n "请输入要删除的规则编号 (输入 'a' 删除所有): "
    read choice
    
    if [ -z "$choice" ]; then
        echo "❌ 输入不能为空"
        return
    fi
    
    if [ "$choice" = "a" ]; then
        # 删除所有规则
        while IFS='|' read -r rule_id src_port dest_ip dest_port protocol; do
            # 删除NAT规则
            if [ "$protocol" = "tcp" ]; then
                iptables -t nat -D PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                iptables -t nat -D POSTROUTING -p tcp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
            elif [ "$protocol" = "udp" ]; then
                iptables -t nat -D PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                iptables -t nat -D POSTROUTING -p udp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
            fi
            
            # 删除UFW规则
            ufw_comment_tcp="PortForward-${rule_id}-TCP"
            ufw_comment_udp="PortForward-${rule_id}-UDP"
            
            # 获取匹配的UFW规则编号
            ufw_rules_tcp=$(ufw status numbered | grep "$ufw_comment_tcp" | awk -F'[][]' '{print $2}' | sort -rn)
            ufw_rules_udp=$(ufw status numbered | grep "$ufw_comment_udp" | awk -F'[][]' '{print $2}' | sort -rn)
            
            # 删除UFW规则（从高编号开始）
            for rule_num in $ufw_rules_tcp $ufw_rules_udp; do
                if [ -n "$rule_num" ]; then
                    yes | ufw delete "$rule_num"
                fi
            done
        done < "$PORT_FORWARD_RULES_FILE"
        
        # 清空规则文件
        > "$PORT_FORWARD_RULES_FILE"
        
        # 保存iptables规则
        iptables-save > /etc/iptables/rules.v4
        
        echo "✅ 所有端口转发规则已删除"
        
        # 检查是否还有转发规则
        check_forwarding_rules
    else
        # 获取选择的规则ID
        declare -A rule_groups
        group_count=0
        while IFS='|' read -r rule_id src_port dest_ip dest_port protocol; do
            if [ -z "${rule_groups[$rule_id]}" ]; then
                rule_groups[$rule_id]="$src_port|$dest_ip|$dest_port|$protocol"
                ((group_count++))
            else
                # 合并相同规则ID的协议
                existing="${rule_groups[$rule_id]}"
                protocols=$(echo "$existing" | cut -d'|' -f4)
                rule_groups[$rule_id]="$(echo "$existing" | cut -d'|' -f1-3)|${protocols},$protocol"
            fi
        done < "$PORT_FORWARD_RULES_FILE"
        
        # 获取选择的规则ID
        local selected_rule_id
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$group_count" ]; then
            local idx=1
            for rule_id in "${!rule_groups[@]}"; do
                if [ "$idx" -eq "$choice" ]; then
                    selected_rule_id="$rule_id"
                    break
                fi
                ((idx++))
            done
        else
            echo "❌ 无效的选择: $choice"
            return
        fi
        
        if [ -z "$selected_rule_id" ]; then
            echo "❌ 未找到规则"
            return
        fi
        
        # 删除该规则ID的所有记录
        while IFS='|' read -r rule_id src_port dest_ip dest_port protocol; do
            if [ "$rule_id" = "$selected_rule_id" ]; then
                # 删除NAT规则
                if [ "$protocol" = "tcp" ]; then
                    iptables -t nat -D PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                    iptables -t nat -D POSTROUTING -p tcp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                elif [ "$protocol" = "udp" ]; then
                    iptables -t nat -D PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "${dest_ip}:${dest_port}"
                    iptables -t nat -D POSTROUTING -p udp -d "$dest_ip" --dport "$dest_port" -j MASQUERADE
                fi
                
                # 删除UFW规则
                ufw_comment="PortForward-${rule_id}-${protocol^^}"
                
                # 获取匹配的UFW规则编号
                ufw_rules=$(ufw status numbered | grep "$ufw_comment" | awk -F'[][]' '{print $2}' | sort -rn)
                
                # 删除UFW规则（从高编号开始）
                for rule_num in $ufw_rules; do
                    if [ -n "$rule_num" ]; then
                        yes | ufw delete "$rule_num"
                    fi
                done
                
                # 从规则文件中删除记录
                delete_forward_rule "$rule_id"
            fi
        done < "$PORT_FORWARD_RULES_FILE"
        
        # 保存iptables规则
        iptables-save > /etc/iptables/rules.v4
        
        echo "✅ 端口转发规则 $selected_rule_id 已删除"
        
        # 检查是否还有转发规则
        check_forwarding_rules
    fi
}

# 端口转发设置
port_forwarding() {
    # 确保目录存在
    mkdir -p /etc/iptables
    mkdir -p "$(dirname "$PORT_FORWARD_RULES_FILE")"

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
            1) # 添加端口转发
                add_port_forward
                ;;
            2) # 查看端口转发规则
                show_port_forwards
                echo "---------------------------------------------------"
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3) # 删除端口转发规则
                delete_port_forward
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

# 启用防火墙并应用规则
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
    echo -n "⚠️ 确定要重置防火墙吗? 所有规则将被删除! [y/N]: "
    read confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        ufw --force reset
        # 同时清除端口转发规则
        > "$PORT_FORWARD_RULES_FILE"
        iptables -t nat -F
        iptables-save > /etc/iptables/rules.v4
        echo "✅ 防火墙已重置"
        echo "⚠️ 注意: 变更将在重载防火墙后生效"
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

    # 备份当前脚本
    BACKUP_FILE="${INSTALL_PATH}.bak-$(date +%Y%m%d%H%M%S)"
    cp "$INSTALL_PATH" "$BACKUP_FILE"
    echo "✅ 当前脚本已备份到: $BACKUP_FILE"

    # 下载最新版本
    echo "下载最新版本..."
    wget -q -O "$INSTALL_PATH" "$SCRIPT_URL"

    if [ $? -eq 0 ]; then
        # 设置执行权限
        chmod 755 "$INSTALL_PATH"
        echo "✅ 脚本已更新到最新版本"
        echo "⚠️ 请重新运行脚本以使更新生效"
        echo "项目地址: $GITHUB_REPO"

        # 询问是否重新运行
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

# 卸载脚本
uninstall_script() {
    clear
    echo "===================== 卸载脚本 ===================="
    echo "⚠️ 警告: 此操作将卸载 UFW 防火墙管理工具"
    echo "      也可能会删除 UFW 防火墙本身，取决于你的选择"
    echo "---------------------------------------------------"
    echo -n "确定要卸载吗? [y/N]: "
    read confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 删除安装的脚本
        if [ -f "$INSTALL_PATH" ]; then
            rm -f "$INSTALL_PATH"
            echo "✅ 已删除安装的脚本: $INSTALL_PATH"
        fi
        
        # 删除端口转发规则文件
        if [ -f "$PORT_FORWARD_RULES_FILE" ]; then
            rm -f "$PORT_FORWARD_RULES_FILE"
            echo "✅ 已删除端口转发规则文件"
        fi

        # 询问是否卸载UFW
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

# 主函数
main() {
    check_root

    # 首次运行时自动安装到系统路径
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

# 启动主函数
main