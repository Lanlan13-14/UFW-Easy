#!/bin/bash
SCRIPT_TAG="PortForwardScript"

# 检查 UFW 是否存在
check_ufw() {
    if ! command -v ufw >/dev/null 2>&1; then
        echo "⚠️ 未检测到 ufw 命令，跳过 UFW 操作"
        return 1
    fi
    return 0
}

# 自动添加 UFW 放行规则
add_ufw_rule() {
    local port="$1"
    local proto="$2"
    check_ufw && ufw allow "${port}/${proto}" >/dev/null 2>&1
}

# 自动删除 UFW 放行规则
del_ufw_rule() {
    local port="$1"
    local proto="$2"
    check_ufw && ufw delete allow "${port}/${proto}" >/dev/null 2>&1
}

# 删除 UFW 规则，支持端口段
del_ufw_range() {
    local start="$1"
    local end="$2"
    local proto="$3"
    for ((p=start; p<=end; p++)); do
        del_ufw_rule "$p" "$proto"
    done
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
    echo "6. 同步 UFW 规则"
    echo "0. 退出"
    echo "=============================="
}

# 添加单端口转发
add_single_port_forward() {
    read -p "请输入本机监听端口: " LOCAL_PORT
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标服务器端口: " TARGET_PORT

    select_protocol

    for PROTO in "${PROTOS[@]}"; do
        iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
            -j DNAT --to-destination $TARGET_IP:$TARGET_PORT \
            -m comment --comment "$SCRIPT_TAG"
        iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP --dport $TARGET_PORT \
            -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
        add_ufw_rule "$LOCAL_PORT" "$PROTO"
    done

    echo "✅ 已添加单个端口转发并同步 UFW: 本机 $LOCAL_PORT → $TARGET_IP:$TARGET_PORT (${PROTOS[*]})"
}

# 添加端口段转发
add_port_range_forward() {
    read -p "请输入本机起始端口: " LOCAL_START
    read -p "请输入本机结束端口: " LOCAL_END
    read -p "请输入目标服务器 IP: " TARGET_IP
    read -p "请输入目标起始端口: " TARGET_START

    select_protocol

    for PROTO in "${PROTOS[@]}"; do
        iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
            -j DNAT --to-destination $TARGET_IP:$TARGET_START \
            -m comment --comment "$SCRIPT_TAG"
        iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_IP \
            --dport $TARGET_START:$((TARGET_START + LOCAL_END - LOCAL_START)) \
            -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
        for ((p=LOCAL_START; p<=LOCAL_END; p++)); do
            add_ufw_rule "$p" "$PROTO"
        done
    done

    echo "✅ 已添加端口段转发并同步 UFW: 本机 $LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-... (${PROTOS[*]})"
}

# 删除指定规则（全链路清理）
delete_specific_rule() {
    echo "📜 当前本脚本添加的规则:"
    mapfile -t nat_rules < <(iptables -t nat -S | grep "$SCRIPT_TAG")
    if [ ${#nat_rules[@]} -eq 0 ]; then
        echo "⚠️ 没有找到本脚本的规则"
        return
    fi

    for i in "${!nat_rules[@]}"; do
        echo "$((i+1)). ${nat_rules[$i]}"
    done

    read -p "请输入要删除的规则编号: " num
    if [[ $num =~ ^[0-9]+$ ]] && [ $num -gt 0 ] && [ $num -le ${#nat_rules[@]} ]; then
        rule="${nat_rules[$((num-1))]}"

        # 提取协议、端口信息
        if [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
            proto="${BASH_REMATCH[1]}"
            start="${BASH_REMATCH[2]}"
            end="${BASH_REMATCH[3]}"
            del_ufw_range "$start" "$end" "$proto"
        elif [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+) ]]; then
            proto="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            del_ufw_rule "$port" "$proto"
        fi

        # 删除 NAT 表中所有匹配此规则协议/端口的规则
        proto_match=$(echo "$rule" | grep -oP '(?<=-p )\S+')
        port_match=$(echo "$rule" | grep -oP '(?<=--dport )\S+')
        for table in nat filter; do
            iptables -t $table -S | grep "$SCRIPT_TAG" | grep -E "$proto_match" | grep -E "$port_match" | while read -r r; do
                iptables -t $table ${r//-A/-D}
            done
        done

        echo "✅ 已删除规则及相关链路"
    else
        echo "❌ 输入无效"
    fi
}

# 清空所有规则（全链路清理）
clear_all_rules() {
    echo "🗑 清空所有本脚本添加的规则..."
    for table in nat filter; do
        iptables -t $table -S | grep "$SCRIPT_TAG" | while read -r rule; do
            if [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
                del_ufw_range "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[1]}"
            elif [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+) ]]; then
                del_ufw_rule "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
            fi
            iptables -t $table ${rule//-A/-D}
        done
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

# 同步 UFW 规则
sync_ufw_rules() {
    echo "🔄 正在同步 UFW 规则..."
    check_ufw || return

    iptables -t nat -S | grep "$SCRIPT_TAG" | while read -r rule; do
        if [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
            proto="${BASH_REMATCH[1]}"
            start="${BASH_REMATCH[2]}"
            end="${BASH_REMATCH[3]}"
            for ((p=start; p<=end; p++)); do
                if ! ufw status numbered | grep -qE "ALLOW[[:space:]]+.*$p/$proto"; then
                    ufw allow "$p/$proto" >/dev/null 2>&1
                    echo "✅ 已补充 UFW 规则: $p/$proto"
                fi
            done
        elif [[ "$rule" =~ -p[[:space:]]+([a-z]+).*--dport[[:space:]]+([0-9]+) ]]; then
            proto="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            if ! ufw status numbered | grep -qE "ALLOW[[:space:]]+.*$port/$proto"; then
                ufw allow "$port/$proto" >/dev/null 2>&1
                echo "✅ 已补充 UFW 规则: $port/$proto"
            fi
        fi
    done
    echo "🔄 同步完成"
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
        6) sync_ufw_rules ;;
        0) echo "👋 退出"; exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
done