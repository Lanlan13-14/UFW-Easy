#!/bin/bash
SCRIPT_TAG="PortForwardScript"

# 检查 UFW 是否启用
is_ufw_enabled() {
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        return 0
    fi
    return 1
}

# 添加 UFW 规则
add_ufw_rule() {
    local port="$1"
    local proto="$2"
    if is_ufw_enabled; then
        ufw allow "$port/$proto" >/dev/null 2>&1
        echo "🔓 已添加 UFW 放行: $port/$proto"
    fi
}

# 删除 UFW 规则
delete_ufw_rule() {
    local port="$1"
    local proto="$2"
    if is_ufw_enabled; then
        ufw delete allow "$port/$proto" >/dev/null 2>&1
        echo "🔒 已删除 UFW 放行: $port/$proto"
    fi
}

# 协议选择函数
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

# 菜单
show_menu() {
    echo "=============================="
    echo "🎯 端口转发管理工具"
    echo "=============================="
    echo "1. 添加单个端口转发"
    echo "2. 添加端口段转发"
    echo "3. 删除指定规则"
    echo "4. 清空所有本脚本规则"
    echo "5. 查看当前规则"
    echo "0. 退出"
    echo "=============================="
}

# 添加单端口转发
add_single_port_forward() {
    read -p "请输入本机监听端口: " LOCAL_PORT
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标服务器端口: " TARGET_PORT

    select_protocol  # 每个转发单独选协议

    for PROTO in "${PROTOS[@]}"; do
        iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
            -j DNAT --to-destination $TARGET_IP:$TARGET_PORT \
            -m comment --comment "$SCRIPT_TAG"
        iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP --dport $TARGET_PORT \
            -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
        add_ufw_rule "$LOCAL_PORT" "$PROTO"
    done

    echo "✅ 已添加单个端口转发: 本机 $LOCAL_PORT → $TARGET_IP:$TARGET_PORT (${PROTOS[*]})"
}

# 添加端口段转发
add_port_range_forward() {
    read -p "请输入本机起始端口: " LOCAL_START
    read -p "请输入本机结束端口: " LOCAL_END
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标起始端口: " TARGET_START

    select_protocol  # 每个转发单独选协议

    for PROTO in "${PROTOS[@]}"; do
        iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
            -j DNAT --to-destination $TARGET_IP:$TARGET_START \
            -m comment --comment "$SCRIPT_TAG"
        iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP \
            --dport $TARGET_START:$((TARGET_START + LOCAL_END - LOCAL_START)) \
            -j MASQUERADE -m comment --comment "$SCRIPT_TAG"

        # 批量放行 UFW
        if is_ufw_enabled; then
            for port in $(seq "$LOCAL_START" "$LOCAL_END"); do
                add_ufw_rule "$port" "$PROTO"
            done
        fi
    done

    echo "✅ 已添加端口段转发: 本机 $LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-... (${PROTOS[*]})"
}

# 删除指定规则
delete_specific_rule() {
    echo "📜 当前本脚本添加的规则:"
    mapfile -t nat_rules < <(iptables -t nat -S | grep "$SCRIPT_TAG")
    mapfile -t fwd_rules < <(iptables -S FORWARD | grep "$SCRIPT_TAG")

    all_rules=("${nat_rules[@]/#/nat }" "${fwd_rules[@]/#/filter }")

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
        table=${rule%% *}
        rule_str=${rule#* }
        echo "🗑 删除规则: $rule"
        iptables -t $table ${rule_str//-A/-D}
        iptables -t $table ${rule_str//-I/-D}

        # 尝试从规则里解析端口+协议删除 UFW 规则
        if [[ "$rule_str" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+) ]]; then
            proto="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            delete_ufw_rule "$port" "$proto"
        fi

        echo "✅ 删除完成"
    else
        echo "❌ 输入无效"
    fi
}

# 清空所有规则
clear_all_rules() {
    echo "🗑 清空所有本脚本添加的规则..."
    for table in nat filter; do
        rules=$(iptables -t $table -S | grep "$SCRIPT_TAG")
        while read -r rule; do
            if [ -n "$rule" ]; then
                iptables -t $table ${rule//-A/-D}
                # 尝试解析端口和协议，删除 UFW
                if [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+) ]]; then
                    proto="${BASH_REMATCH[1]}"
                    port="${BASH_REMATCH[2]}"
                    delete_ufw_rule "$port" "$proto"
                fi
            fi
        done <<< "$rules"
    done
    echo "✅ 已清空"
}

# 查看规则
list_rules() {
    echo "📜 NAT 表规则:"
    iptables -t nat -S | grep "$SCRIPT_TAG" || echo "（无）"
    echo
    echo "📜 FORWARD 链规则:"
    iptables -S FORWARD | grep "$SCRIPT_TAG" || echo "（无）"
}

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