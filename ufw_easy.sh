#!/usr/bin/env bash

# ===========================================================
# 增强版 UFW 防火墙管理工具
# 版本: 5.1
# 项目地址: https://github.com/Lanlan13-14/UFW-Easy
# 特点: 
#   - 自动安装 UFW 但不自动启用
#   - 所有规则变更需手动重载才生效
#   - 规则自动优先于默认拒绝策略
#   - 支持更新脚本功能
#   - 支持 TCP/UDP 协议选择
# ===========================================================

# 项目信息
GITHUB_REPO="https://github.com/Lanlan13-14/UFW-Easy"
SCRIPT_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/ufw_easy.sh"
UNINSTALL_URL="https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/main/uninstall.sh"

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
    echo "          增强版 UFW 防火墙管理工具"
    echo "  项目地址: ${GITHUB_REPO}"
    echo "          版本: 5.1"
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
    # 修复点：为 $rule 添加双引号
    if ! ufw insert 1 "$rule"; then
        # 如果插入失败（可能因为第一条规则已存在），则追加规则
        ufw "$rule"
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
                # 修复点：正确处理 TCP+UDP 协议
                # 对于单端口，使用 "port" 语法
                # 对于端口范围，使用 "port:port" 语法
                local port_syntax="port"
                if [[ "$port" == *:* ]]; then
                    port_syntax="ports"
                fi
                
                if [ -z "$ip" ]; then
                    add_rule "$rule_type $port"
                else
                    add_rule "$rule_type from $ip to any $port_syntax $port"
                fi
                read -n 1 -s -r -p "✅ 规则已添加（TCP+UDP），按任意键继续..."
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
                    # 组合端口范围
                    port_range="${start_port}:${end_port}"
                    # 复用协议选择菜单
                    show_protocol_menu "$port_range" "allow" "$ip"
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
                                # 修复点：正确处理 TCP+UDP 协议
                                add_rule "allow in on $interface to any port $port"
                                echo "✅ 规则已添加: 允许 $interface 接口上的 $port (TCP+UDP) 访问"
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

# 删除规则（智能识别输入格式） - 修复点
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
            # 修复点：使用正确的重置命令替代 --force 参数
            yes | ufw reset
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
            # 修复点：正确删除规则（去掉 --force 参数）
            if ufw delete "$cleaned_num"; then
                echo "✅ 规则 $cleaned_num 已删除 (输入: $rule_num)"
                echo "⚠️ 注意: 变更将在重载防火墙后生效"
            else
                echo "❌ 删除规则失败，请检查规则编号是否正确"
            fi
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

# 端口转发设置 - 使用新脚本
# 修复点：重命名函数避免冲突
setup_port_forwarding() {
    clear
    echo "正在下载并执行端口转发脚本..."

    # 临时脚本路径
    TEMP_SCRIPT="/tmp/port_forward.sh"

    # 下载脚本
    curl -L -o "$TEMP_SCRIPT" https://raw.githubusercontent.com/Lanlan13-14/UFW-Easy/refs/heads/main/port_forward.sh

    if [ $? -ne 0 ]; then
        echo "❌ 下载端口转发脚本失败，请检查网络连接"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return
    fi

    # 设置执行权限
    chmod +x "$TEMP_SCRIPT"

    # 执行脚本
    "$TEMP_SCRIPT"

    echo "端口转发脚本执行完成"
    read -n 1 -s -r -p "按任意键返回主菜单..."
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
        yes | ufw reset
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

    # 获取当前脚本路径
    CURRENT_SCRIPT=$(readlink -f "$0")

    # 备份当前脚本
    BACKUP_FILE="${CURRENT_SCRIPT}.bak-$(date +%Y%m%d%H%M%S)"
    cp "$CURRENT_SCRIPT" "$BACKUP_FILE"
    echo "✅ 当前脚本已备份到: $BACKUP_FILE"

    # 下载最新版本
    echo "下载最新版本..."
    wget -q -O "$CURRENT_SCRIPT" "$SCRIPT_URL"

    if [ $? -eq 0 ]; then
        # 设置执行权限
        chmod +x "$CURRENT_SCRIPT"

        # 语法检查
        bash -n "$CURRENT_SCRIPT"
        if [ $? -ne 0 ]; then
            echo "❌ 新脚本语法检查失败，已恢复备份"
            mv "$BACKUP_FILE" "$CURRENT_SCRIPT"
            read -n 1 -s -r -p "按任意键返回主菜单..."
            return
        fi

        echo "✅ 脚本已更新到最新版本"
        echo "⚠️ 请重新运行脚本以使更新生效"
        echo "项目地址: $GITHUB_REPO"

        # 询问是否重新运行
        echo -n "是否立即重新运行脚本? [Y/n]: "
        read restart_choice

        if [ -z "$restart_choice" ] || [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
            echo "🔄 重新运行脚本..."
            rm -f "$BACKUP_FILE"   # ✅ 删除备份
            exec "$CURRENT_SCRIPT"
        else
            echo "ℹ️ 您可以选择稍后手动运行: sudo $CURRENT_SCRIPT"
            echo "✅ 已删除备份文件: $BACKUP_FILE"
            rm -f "$BACKUP_FILE"
            exit 0
        fi
    else
        echo "❌ 更新失败，请检查网络连接"
        echo "已恢复备份: $BACKUP_FILE"
        mv "$BACKUP_FILE" "$CURRENT_SCRIPT"
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
        echo "正在执行卸载脚本..."
        # 执行远程卸载脚本
        bash -c "$(curl -sL $UNINSTALL_URL)"
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
            6) setup_port_forwarding ;;  # 使用修复后的函数名
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