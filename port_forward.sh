#!/bin/bash
SCRIPT_TAG="PortForwardScript"

# 检测并安装持久化依赖
check_and_install_persistent() {
    local need_install=0
    if ! command -v netfilter-persistent >/dev/null 2>&1; then
        need_install=1
    fi
    if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
        need_install=1
    fi

    if [ $need_install -eq 1 ]; then
        echo "检测到未安装 netfilter-persistent 或 iptables-persistent，正在自动安装..."
        sudo apt update && sudo apt install -y netfilter-persistent iptables-persistent
        echo "安装完成。"
    fi
}

# 检查 IPv6 支持
has_ipv6() {
    [ -s /proc/net/if_inet6 ]
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

# 获取监听 IP
get_listen_ip() {
    read -p "请输入监听 IP (回车自动选择): " LISTEN_IP
    if [ -z "$LISTEN_IP" ]; then
        if has_ipv6; then
            LISTEN_IP="[::]"
        else
            LISTEN_IP="0.0.0.0"
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

# 添加单端口转发
add_single_port_forward() {
    get_listen_ip
    read -p "请输入本机监听端口: " LOCAL_PORT
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标服务器端口: " TARGET_PORT

    select_protocol

    for PROTO in "${PROTOS[@]}"; do
        # IPv4
        iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
            -j DNAT --to-destination $TARGET_IP:$TARGET_PORT \
            -m comment --comment "$SCRIPT_TAG"
        iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP --dport $TARGET_PORT \
            -j MASQUERADE -m comment --comment "$SCRIPT_TAG"

        # IPv6
        if has_ipv6; then
            ip6tables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
                -j DNAT --to-destination [$TARGET_IP]:$TARGET_PORT \
                -m comment --comment "$SCRIPT_TAG"
            ip6tables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP --dport $TARGET_PORT \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
        fi

        # UFW
        add_ufw_rule "$LOCAL_PORT" "$PROTO"
    done

    save_rules
    echo "✅ 已添加单个端口转发: $LISTEN_IP:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT (${PROTOS[*]})"
}

# 添加端口段转发
add_port_range_forward() {
    get_listen_ip
    read -p "请输入本机起始端口: " LOCAL_START
    read -p "请输入本机结束端口: " LOCAL_END
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标起始端口: " TARGET_START

    select_protocol

    for PROTO in "${PROTOS[@]}"; do
        # IPv4
        iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
            -j DNAT --to-destination $TARGET_IP:$TARGET_START \
            -m comment --comment "$SCRIPT_TAG"
        iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP \
            --dport $TARGET_START:$((TARGET_START + LOCAL_END - LOCAL_START)) \
            -j MASQUERADE -m comment --comment "$SCRIPT_TAG"

        # IPv6
        if has_ipv6; then
            ip6tables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
                -j DNAT --to-destination [$TARGET_IP]:$TARGET_START \
                -m comment --comment "$SCRIPT_TAG"
            ip6tables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP \
                --dport $TARGET_START:$((TARGET_START + LOCAL_END - LOCAL_START)) \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
        fi

        # UFW
        for ((port=LOCAL_START; port<=LOCAL_END; port++)); do
            add_ufw_rule "$port" "$PROTO"
        done
    done

    save_rules
    echo "✅ 已添加端口段转发: $LISTEN_IP:$LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-... (${PROTOS[*]})"
}

# 删除指定规则
delete_specific_rule() {
    echo "📜 当前本脚本添加的规则:"
    mapfile -t all_rules < <(
        iptables -t nat -S | grep "$SCRIPT_TAG" | sed 's/^/ipv4 nat /'
        ip6tables -t nat -S | grep "$SCRIPT_TAG" | sed 's/^/ipv6 nat /'
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
        table="nat"
        rule_str=${rule#* * }

        if [ "$ip_ver" = "ipv4" ]; then
            iptables -t $table ${rule_str//-A/-D}
        else
            ip6tables -t $table ${rule_str//-A/-D}
        fi

        # 删除对应 UFW
        port=$(echo "$rule_str" | grep -oP '(?<=--dport )\d+')
        proto=$(echo "$rule_str" | grep -oP '(?<=-p )\w+')
        if [ -n "$port" ] && [ -n "$proto" ]; then
            del_ufw_rule "$port" "$proto"
        fi

        save_rules
        echo "✅ 已删除规则"
    else
        echo "❌ 输入无效"
    fi
}

# 清空所有规则
clear_all_rules() {
    echo "🗑 清空所有本脚本添加的规则..."
    for cmd in iptables ip6tables; do
        for table in nat filter; do
            rules=$($cmd -t $table -S | grep "$SCRIPT_TAG")
            while read -r rule; do
                [ -n "$rule" ] && $cmd -t $table ${rule//-A/-D}
            done <<< "$rules"
        done
    done

    # 删除 UFW 相关规则
    ufw status numbered | grep "$SCRIPT_TAG" >/dev/null 2>&1 && \
    yes | ufw delete allow comment "$SCRIPT_TAG"

    save_rules
    echo "✅ 已清空"
}

# 保存规则
save_rules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        sudo netfilter-persistent save
    elif command -v service >/dev/null 2>&1; then
        sudo service iptables save >/dev/null 2>&1
        sudo service ip6tables save >/dev/null 2>&1
    fi
}

# 查看规则
list_rules() {
    echo "📜 IPv4 NAT 表:"
    iptables -t nat -S | grep "$SCRIPT_TAG" || echo "（无）"
    echo
    echo "📜 IPv6 NAT 表:"
    ip6tables -t nat -S | grep "$SCRIPT_TAG" || echo "（无）"
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
    echo "0. 退出"
    echo "=============================="
}

# 入口：先检测依赖
check_and_install_persistent

# 主循环
while true; do
    show_menu
    read -p "请选择操作: " choice
    case $choice in
        1) add_single_port_forward ;;
        2) add_port_range_forward ;;
        3) delete_specific_rule ;;
        4) clear_all_rules ;;
        5) list_rules ;;
        0) echo "👋 退出"; exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
done