#!/bin/bash
SCRIPT_TAG="PortForwardScript"
RULES_FILE="/etc/port_forward_rules.sh"
SERVICE_FILE="/etc/systemd/system/portforward.service"

# 三重检测确保真实 IPv6 支持
has_usable_ipv6() {
    # 1. 测试实际网络连接
    if curl -s -6 --connect-timeout 3 https://ipv6.google.com >/dev/null 2>&1; then
        return 0
    fi
    
    # 2. 检查全局 IPv6 地址
    if ip -6 addr show scope global | grep -q 'inet6'; then
        return 0
    fi
    
    # 3. 检查内核支持
    [ -s /proc/net/if_inet6 ]
}

# 地址类型检测
is_ipv4() {
    [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

is_ipv6() {
    [[ $1 =~ : ]]
}

# 协议选择
select_protocol() {
    echo "请选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "输入选择: " proto_choice
    case $proto_choice in
        1) PROTOS=("tcp") ;;
        2) PROTOS=("udp") ;;
        3) PROTOS=("tcp" "udp") ;;
        *) echo "❌ 无效选择，默认 TCP"; PROTOS=("tcp") ;;
    esac
}

# 获取监听 IP (智能双栈处理)
get_listen_ip() {
    read -p "请输入监听 IP (回车自动选择): " LISTEN_IP
    
    # 自动选择逻辑
    if [ -z "$LISTEN_IP" ]; then
        if has_usable_ipv6; then
            LISTEN_IP="dual"  # 双栈模式标记
            echo "✅ 自动选择: 双栈监听 (IPv4+IPv6)"
        else
            LISTEN_IP="0.0.0.0"
            echo "✅ 自动选择: IPv4 (0.0.0.0)"
        fi
    else
        # 规范化 IPv6 地址
        if is_ipv6 "$LISTEN_IP" && [[ ! "$LISTEN_IP" =~ ^\[.*\]$ ]]; then
            LISTEN_IP="[$LISTEN_IP]"
        fi
    fi
}

# 添加 UFW 规则
add_ufw_rule() {
    local port=$1 proto=$2
    ufw allow $port/$proto comment "$SCRIPT_TAG" >/dev/null 2>&1
}

# 删除 UFW 规则
del_ufw_rule() {
    local port=$1 proto=$2
    ufw delete allow $port/$proto >/dev/null 2>&1
}

# 清除所有 iptables 规则
clear_all_iptables_rules() {
    for cmd in iptables ip6tables; do
        for table in nat filter; do
            # 使用更安全的规则删除方法
            $cmd -t $table -S | grep "$SCRIPT_TAG" | awk '{print $2 " " $3}' | while read chain rule; do
                # 按行号倒序删除
                $cmd -t $table -L $chain --line-numbers | grep "$SCRIPT_TAG" | sort -nr | while read line; do
                    rule_num=$(echo $line | awk '{print $1}')
                    $cmd -t $table -D $chain $rule_num
                done
            done
        done
    done
}

# 创建并启用 systemd 服务
enable_systemd_service() {
    if [ ! -f "$SERVICE_FILE" ]; then
        cat << EOF > "$SERVICE_FILE"
[Unit]
Description=恢复端口转发规则
After=network.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $RULES_FILE
RemainAfterExit=yes
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable portforward.service
        systemctl start portforward.service
        echo "✅ systemd 服务 portforward.service 创建并启动"
    else
        systemctl daemon-reload
        systemctl enable portforward.service >/dev/null 2>&1
        systemctl start portforward.service >/dev/null 2>&1
    fi
}

# 停用并删除 systemd 服务
disable_systemd_service() {
    if [ -f "$SERVICE_FILE" ]; then
        systemctl stop portforward.service >/dev/null 2>&1
        systemctl disable portforward.service >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        echo "✅ systemd 服务 portforward.service 已删除"
    fi
}

# 保存规则到文件
save_rules_to_file() {
    echo "#!/bin/bash" > "$RULES_FILE"
    echo "# 自动生成的端口转发规则文件" >> "$RULES_FILE"
    echo "SCRIPT_TAG=\"$SCRIPT_TAG\"" >> "$RULES_FILE"
    echo >> "$RULES_FILE"
    
    # 添加系统配置
    echo "# 系统配置" >> "$RULES_FILE"
    echo "sysctl -w net.ipv4.ip_forward=1" >> "$RULES_FILE"
    echo "sysctl -w net.ipv6.conf.all.forwarding=1" >> "$RULES_FILE"
    echo >> "$RULES_FILE"
    
    # 添加规则命令
    echo "# 转发规则" >> "$RULES_FILE"
    for cmd in iptables ip6tables; do
        for table in nat filter; do
            $cmd -t $table -S | grep "$SCRIPT_TAG" | while read -r line; do
                # 用 -I 保证插入顺序
                echo "${cmd} -t ${table} ${line#-A }" | sed 's/-A /-I /'
            done
        done
    done
    
    chmod +x "$RULES_FILE"
    enable_systemd_service
}

# 添加单端口转发 (支持 NAT64/NAT46)
add_single_port_forward() {
    get_listen_ip
    read -p "请输入本机监听端口: " LOCAL_PORT
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标服务器端口: " TARGET_PORT

    select_protocol

    # 清理旧规则避免重复
    clear_all_iptables_rules

    # 处理监听模式
    IPV4_LISTEN=""
    IPV6_LISTEN=""
    
    case $LISTEN_IP in
        "dual")
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN="[::]"
            echo "🔄 配置双栈监听: IPv4($IPV4_LISTEN) + IPv6($IPV6_LISTEN)"
            ;;
        "0.0.0.0")
            IPV4_LISTEN="0.0.0.0"
            echo "🔄 配置 IPv4 监听: $IPV4_LISTEN"
            ;;
        *)
            if is_ipv4 "$LISTEN_IP"; then
                IPV4_LISTEN="$LISTEN_IP"
                echo "🔄 配置 IPv4 监听: $IPV4_LISTEN"
            elif is_ipv6 "$LISTEN_IP"; then
                IPV6_LISTEN="$LISTEN_IP"
                echo "🔄 配置 IPv6 监听: $IPV6_LISTEN"
            else
                echo "❌ 无效的监听地址: $LISTEN_IP"
                return 1
            fi
            ;;
    esac

    # 添加规则
    for PROTO in "${PROTOS[@]}"; do
        # IPv4 监听规则
        if [ -n "$IPV4_LISTEN" ]; then
            # 目标地址处理
            if is_ipv6 "$TARGET_IP"; then
                echo "🔄 配置 NAT46 转发: IPv4->IPv6"
                TARGET_ADDR="[$TARGET_IP]"
            else
                TARGET_ADDR="$TARGET_IP"
            fi
            
            # 添加 DNAT 规则
            iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_PORT \
                -m comment --comment "$SCRIPT_TAG"
                
            # 添加 MASQUERADE 规则
            iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            # 添加 FORWARD 规则
            iptables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
        fi

        # IPv6 监听规则
        if [ -n "$IPV6_LISTEN" ] && has_usable_ipv6; then
            # 目标地址处理
            if is_ipv4 "$TARGET_IP"; then
                echo "🔄 配置 NAT64 转发: IPv6->IPv4"
                TARGET_ADDR="$TARGET_IP"
            else
                TARGET_ADDR="[$TARGET_IP]"
            fi
            
            # 添加 DNAT 规则
            ip6tables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_PORT \
                -m comment --comment "$SCRIPT_TAG"
                
            # 添加 MASQUERADE 规则
            ip6tables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            # 添加 FORWARD 规则
            ip6tables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
        fi

        # UFW 规则
        if [ -n "$IPV4_LISTEN" ]; then
            add_ufw_rule "$LOCAL_PORT" "$PROTO"
        fi
    done

    save_rules_to_file
    echo "✅ 已添加端口转发:"
    [ -n "$IPV4_LISTEN" ] && echo "  IPv4: $IPV4_LISTEN:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT"
    [ -n "$IPV6_LISTEN" ] && echo "  IPv6: $IPV6_LISTEN:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT"
    echo "  协议: ${PROTOS[*]}"
}

# 添加端口段转发
add_port_range_forward() {
    get_listen_ip
    read -p "请输入本机起始端口: " LOCAL_START
    read -p "请输入本机结束端口: " LOCAL_END
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标起始端口: " TARGET_START

    select_protocol

    # 计算目标端口范围
    PORT_COUNT=$((LOCAL_END - LOCAL_START + 1))
    TARGET_END=$((TARGET_START + PORT_COUNT - 1))

    # 处理监听模式
    IPV4_LISTEN=""
    IPV6_LISTEN=""
    
    case $LISTEN_IP in
        "dual")
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN="[::]"
            echo "🔄 配置双栈监听: IPv4($IPV4_LISTEN) + IPv6($IPV6_LISTEN)"
            ;;
        "0.0.0.0")
            IPV4_LISTEN="0.0.0.0"
            echo "🔄 配置 IPv4 监听: $IPV4_LISTEN"
            ;;
        *)
            if is_ipv4 "$LISTEN_IP"; then
                IPV4_LISTEN="$LISTEN_IP"
                echo "🔄 配置 IPv4 监听: $IPV4_LISTEN"
            elif is_ipv6 "$LISTEN_IP"; then
                IPV6_LISTEN="$LISTEN_IP"
                echo "🔄 配置 IPv6 监听: $IPV6_LISTEN"
            else
                echo "❌ 无效的监听地址: $LISTEN_IP"
                return 1
            fi
            ;;
    esac

    clear_all_iptables_rules

    # 添加规则
    for PROTO in "${PROTOS[@]}"; do
        # IPv4 监听规则
        if [ -n "$IPV4_LISTEN" ]; then
            # 目标地址处理
            if is_ipv6 "$TARGET_IP"; then
                TARGET_ADDR="[$TARGET_IP]"
            else
                TARGET_ADDR="$TARGET_IP"
            fi
            
            # 添加 DNAT 规则
            iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_START-$TARGET_END \
                -m comment --comment "$SCRIPT_TAG"
                
            # 添加 MASQUERADE 规则
            iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR \
                --dport $TARGET_START:$TARGET_END \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            # 添加 FORWARD 规则
            iptables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_START:$TARGET_END \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
        fi

        # IPv6 监听规则
        if [ -n "$IPV6_LISTEN" ] && has_usable_ipv6; then
            # 目标地址处理
            if is_ipv4 "$TARGET_IP"; then
                TARGET_ADDR="$TARGET_IP"
            else
                TARGET_ADDR="[$TARGET_IP]"
            fi
            
            # 添加 DNAT 规则
            ip6tables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_START-$TARGET_END \
                -m comment --comment "$SCRIPT_TAG"
                
            # 添加 MASQUERADE 规则
            ip6tables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR \
                --dport $TARGET_START:$TARGET_END \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            # 添加 FORWARD 规则
            ip6tables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_START:$TARGET_END \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
        fi

        # UFW 规则
        if [ -n "$IPV4_LISTEN" ]; then
            for ((port=LOCAL_START; port<=LOCAL_END; port++)); do
                add_ufw_rule "$port" "$PROTO"
            done
        fi
    done

    save_rules_to_file
    echo "✅ 已添加端口段转发:"
    [ -n "$IPV4_LISTEN" ] && echo "  IPv4: $IPV4_LISTEN:$LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-$TARGET_END"
    [ -n "$IPV6_LISTEN" ] && echo "  IPv6: $IPV6_LISTEN:$LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-$TARGET_END"
    echo "  协议: ${PROTOS[*]}"
}

# 删除指定规则
delete_specific_rule() {
    echo "📜 当前本脚本添加的规则:"
    mapfile -t all_rules < <(
        iptables -t nat -S | grep "$SCRIPT_TAG" | sed 's/^/ipv4 nat /'
        ip6tables -t nat -S | grep "$SCRIPT_TAG" | sed 's/^/ipv6 nat /'
        iptables -t filter -S | grep "$SCRIPT_TAG" | sed 's/^/ipv4 filter /'
        ip6tables -t filter -S | grep "$SCRIPT_TAG" | sed 's/^/ipv6 filter /'
    )

    if [ ${#all_rules[@]} -eq 0 ]; then
        echo "⚠️ 没有找到本脚本的规则"
        return
    fi

    for i in "${!all_rules[@]}"; do
        echo "$((i+1)). ${all_rules[$i]}"
    done

    read -p "请输入要删除的规则编号: " num
    if [[ $num =~ ^[0-9]+$ ]] && [ $num -gt 0 ] && [ $num -le ${#all_rules[@]} ]; then
        rule="${all_rules[$((num-1))]}"
        ip_ver=${rule%% *}
        table=${rule#* * }
        table=${table%% *}
        rule_str=${rule#* * * }

        if [ "$ip_ver" = "ipv4" ]; then
            rule_str="${rule_str/-A/-D}"
            iptables -t $table $rule_str
        else
            rule_str="${rule_str/-A/-D}"
            ip6tables -t $table $rule_str
        fi

        # 删除对应 UFW
        if [[ "$rule_str" =~ --dport[[:space:]]+([0-9]+) ]]; then
            port="${BASH_REMATCH[1]}"
            proto=$(echo "$rule_str" | grep -oP '(?<=-p )\w+')
            if [ -n "$port" ] && [ -n "$proto" ]; then
                del_ufw_rule "$port" "$proto"
            fi
        fi

        save_rules_to_file
        echo "✅ 已删除规则"
    else
        echo "❌ 输入无效"
    fi
}

# 清空所有规则
clear_all_rules() {
    echo "🗑 清空所有本脚本添加的规则..."
    clear_all_iptables_rules

    # 删除 UFW 相关规则
    if command -v ufw >/dev/null 2>&1; then
        ufw status numbered | grep "$SCRIPT_TAG" | awk -F'[][]' '{print $2}' | tr -d ' ' | sort -rn | while read rule_num; do
            yes | ufw delete $rule_num >/dev/null 2>&1
        done
    fi

    save_rules_to_file

    disable_systemd_service
    echo "✅ 已清空并删除 systemd 服务"
}

# 查看规则
list_rules() {
    echo "📜 IPv4 NAT 表:"
    iptables -t nat -S | grep "$SCRIPT_TAG" || echo "（无）"
    echo
    echo "📜 IPv6 NAT 表:"
    ip6tables -t nat -S | grep "$SCRIPT_TAG" || echo "（无）"
    echo
    echo "📜 IPv4 FILTER 表:"
    iptables -t filter -S | grep "$SCRIPT_TAG" || echo "（无）"
    echo
    echo "📜 IPv6 FILTER 表:"
    ip6tables -t filter -S | grep "$SCRIPT_TAG" || echo "（无）"
}

# 同步 UFW 规则
sync_ufw_rules() {
    echo "🔄 正在同步 UFW 规则..."
    if ! command -v ufw >/dev/null 2>&1; then
        echo "⚠️ 未检测到 ufw 命令，跳过同步"
        return
    fi

    # 从现有规则中提取端口信息
    declare -A ports_to_add
    for cmd in iptables ip6tables; do
        $cmd -t nat -S | grep "$SCRIPT_TAG" | while read -r rule; do
            proto=$(echo "$rule" | grep -oP '(?<=-p )\w+')
            if [[ "$rule" =~ --dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
                start_port="${BASH_REMATCH[1]}"
                end_port="${BASH_REMATCH[2]}"
                for ((p=start_port; p<=end_port; p++)); do
                    ports_to_add["$p/$proto"]=1
                done
            elif [[ "$rule" =~ --dport[[:space:]]+([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
                ports_to_add["$port/$proto"]=1
            fi
        done
    done

    # 添加缺失的 UFW 规则
    for port_proto in "${!ports_to_add[@]}"; do
        if ! ufw status | grep -qE "$port_proto.*$SCRIPT_TAG"; then
            ufw allow "$port_proto" comment "$SCRIPT_TAG" >/dev/null 2>&1
            echo "✅ 已补充 UFW 规则: $port_proto"
        fi
    done

    echo "🔄 同步完成"
}

# 确保 IP 转发已启用
ensure_ip_forwarding() {
    # IPv4 转发
    if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
        echo "⚠️ 启用 IPv4 转发..."
        sysctl -w net.ipv4.ip_forward=1
        grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf && \
            sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf || \
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    # IPv6 转发
    if has_usable_ipv6 && [ "$(sysctl -n net.ipv6.conf.all.forwarding)" != "1" ]; then
        echo "⚠️ 启用 IPv6 转发..."
        sysctl -w net.ipv6.conf.all.forwarding=1
        grep -q '^net.ipv6.conf.all.forwarding' /etc/sysctl.conf && \
            sed -i 's/^net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf || \
            echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
}

# 菜单
show_menu() {
    echo "=============================="
    echo "🎯 端口转发管理工具"
    echo "=============================="
    echo "1. 添加单个端口转发"
    echo "2. 添加端口段转发"
    echo "3. 删除指定规则"
    echo "4. 清空所有规则"
    echo "5. 查看当前规则"
    echo "6. 同步 UFW 规则"
    echo "0. 退出"
    echo "=============================="
}

# 主循环
ensure_ip_forwarding
while true; do
    show_menu
    read -p "请选择操作: " choice
    case $choice in
        1) add_single_port_forward ;;
        2) add_port_range_forward ;;
        3) delete_specific_rule ;;
        4) clear_all_rules ;;
        5) list_rules ;;
        6) sync_ufw_rules ;;
        0) echo "👋 退出"; exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
    echo
done