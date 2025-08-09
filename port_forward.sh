#!/bin/bash
# 端口转发脚本 v3.0
# 单端口/端口段选择 & 删除时可选择具体规则 & Emoji

SCRIPT_TAG="PortForwardScript"

# 持久化 IP 转发
setup_ip_forward_persistent() {
    echo "⚙️  启用 IP 转发..."
    sysctl -w net.ipv4.ip_forward=1
    if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i "s/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/" /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
}

# 添加规则
install_rules() {
    echo "🚀 添加端口转发规则"
    echo "1️⃣ 单端口转发"
    echo "2️⃣ 端口段转发"
    read -p "请选择 [1-2]: " choice

    read -p "请输入目标 IP: " B_IP

    if [ "$choice" == "1" ]; then
        read -p "请输入端口号: " PORT
        PORT_RANGE="$PORT"
    elif [ "$choice" == "2" ]; then
        read -p "请输入起始端口: " PORT_START
        read -p "请输入结束端口: " PORT_END
        PORT_RANGE="$PORT_START:$PORT_END"
    else
        echo "❌ 选择错误"
        return
    fi

    setup_ip_forward_persistent

    echo "🔗 添加 NAT 规则..."
    iptables -t nat -A PREROUTING -p tcp --dport $PORT_RANGE -j DNAT --to-destination $B_IP -m comment --comment "$SCRIPT_TAG"
    iptables -t nat -A POSTROUTING -p tcp -d $B_IP --dport $PORT_RANGE -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
    iptables -t nat -A PREROUTING -p udp --dport $PORT_RANGE -j DNAT --to-destination $B_IP -m comment --comment "$SCRIPT_TAG"
    iptables -t nat -A POSTROUTING -p udp -d $B_IP --dport $PORT_RANGE -j MASQUERADE -m comment --comment "$SCRIPT_TAG"

    echo "📡 添加 FORWARD 规则..."
    iptables -I FORWARD -p tcp -d $B_IP --dport $PORT_RANGE -j ACCEPT -m comment --comment "$SCRIPT_TAG"
    iptables -I FORWARD -p udp -d $B_IP --dport $PORT_RANGE -j ACCEPT -m comment --comment "$SCRIPT_TAG"

    echo "✅ 规则添加成功"
}

# 删除规则（方法 2：编号选择删除）
remove_rules() {
    echo "🗑 删除端口转发规则"
    echo "📜 当前 NAT 规则:"
    mapfile -t nat_rules < <(iptables -t nat -S | grep "$SCRIPT_TAG")
    mapfile -t fwd_rules < <(iptables -S FORWARD | grep "$SCRIPT_TAG")

    if [ ${#nat_rules[@]} -eq 0 ] && [ ${#fwd_rules[@]} -eq 0 ]; then
        echo "⚠️ 没有找到任何规则"
        return
    fi

    all_rules=("${nat_rules[@]/#/nat }" "${fwd_rules[@]/#/fwd }")

    for i in "${!all_rules[@]}"; do
        echo "$((i+1)). ${all_rules[$i]}"
    done

    read -p "请输入要删除的规则编号: " num
    if [[ $num =~ ^[0-9]+$ ]] && [ $num -le ${#all_rules[@]} ] && [ $num -gt 0 ]; then
        rule="${all_rules[$((num-1))]}"
        table=${rule%% *}
        rule_str=${rule#* }
        echo "🗑 删除: $rule_str"
        iptables -t $table ${rule_str//-A/-D}
        iptables -t $table ${rule_str//-I/-D}
        echo "✅ 删除成功"
    else
        echo "❌ 输入无效"
    fi
}

# 查看规则
show_rules() {
    echo "📜 当前 NAT 规则:"
    iptables -t nat -S | grep "$SCRIPT_TAG" || echo "⚠️ 没有找到 NAT 规则"
    echo
    echo "📜 当前 FORWARD 规则:"
    iptables -S FORWARD | grep "$SCRIPT_TAG" || echo "⚠️ 没有找到 FORWARD 规则"
}

# 主菜单
while true; do
    echo
    echo "=== 🛠 端口转发管理菜单 ==="
    echo "1️⃣ 添加端口转发"
    echo "2️⃣ 删除端口转发"
    echo "3️⃣ 查看规则"
    echo "4️⃣ 退出"
    read -p "请选择 [1-4]: " opt

    case $opt in
        1) install_rules ;;
        2) remove_rules ;;
        3) show_rules ;;
        4) echo "👋 再见"; exit ;;
        *) echo "❌ 无效选择" ;;
    esac
done