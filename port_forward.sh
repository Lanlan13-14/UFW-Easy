#!/bin/bash
SCRIPT_TAG="PortForwardScript"
RULES_FILE="/etc/port_forward_rules.sh"
SERVICE_FILE="/etc/systemd/system/portforward.service"
NAT64_PREFIX="64:ff9b::"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
check_root() {
    [ "$(id -u)" = "0" ] || { echo -e "${RED}错误：此脚本必须以root权限运行${NC}" >&2; exit 1; }
}

# 安装必要依赖
install_dependencies() {
    local pkgs="curl iptables git ufw"
    echo -e "${YELLOW}正在检查系统依赖...${NC}"
    if command -v apt >/dev/null; then
        apt update
        apt install -y $pkgs kmod git make gcc linux-headers-$(uname -r)
    elif command -v yum >/dev/null; then
        yum install -y $pkgs kernel-devel git make gcc
    else
        echo -e "${RED}不支持的包管理器，请手动安装依赖${NC}"
        return 1
    fi
}

# NAT64模块管理
manage_nat64() {
    # 安装nat46模块
    if ! lsmod | grep -q "nat46" && has_usable_ipv6; then
        echo -e "${YELLOW}正在配置NAT64/NAT46支持...${NC}"
        
        [ ! -d "/tmp/nat46" ] && git clone https://github.com/ayourtch/nat46.git /tmp/nat46
        cd /tmp/nat46 && make && make install
        modprobe nat46
        echo "nat46" > /etc/modules-load.d/nat46.conf
        
        # 配置NAT64网络
        ip -6 route add local ${NAT64_PREFIX}/96 dev lo 2>/dev/null
        ip6tables -t nat -A POSTROUTING -s ${NAT64_PREFIX}/96 -j MASQUERADE -m comment --comment "NAT64"
    fi
}

# 网络检测函数
has_usable_ipv6() {
    curl -s -6 --connect-timeout 3 https://ipv6.google.com >/dev/null || \
    ip -6 addr show scope global | grep -q 'inet6' || \
    [ -s /proc/net/if_inet6 ]
}

# 地址处理函数
is_ipv4() { [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }
is_ipv6() { [[ $1 =~ : ]]; }
ipv4_to_nat64() { echo "${NAT64_PREFIX}$(echo $1 | sed 's/\./:/g')"; }

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
        *) echo -e "${RED}无效选择，默认使用TCP${NC}"; PROTOS=("tcp") ;;
    esac
}

# 获取监听IP
get_listen_ip() {
    read -p "请输入监听IP (回车自动选择): " LISTEN_IP
    [ -z "$LISTEN_IP" ] && {
        if has_usable_ipv6; then
            LISTEN_IP="dual"
            echo -e "${GREEN}自动选择: 双栈监听 (IPv4+IPv6)${NC}"
        else
            LISTEN_IP="0.0.0.0"
            echo -e "${GREEN}自动选择: IPv4 (0.0.0.0)${NC}"
        fi
        return
    }
    is_ipv6 "$LISTEN_IP" && [[ ! "$LISTEN_IP" =~ ^\[.*\]$ ]] && LISTEN_IP="[$LISTEN_IP]"
}

# UFW规则管理
manage_ufw_rule() {
    local action=$1 port=$2 proto=$3
    case $action in
        add)
            ufw allow $port/$proto comment "$SCRIPT_TAG" >/dev/null && \
            echo -e "${GREEN}UFW规则已添加: $port/$proto${NC}"
            ;;
        del)
            ufw delete allow $port/$proto >/dev/null && \
            echo -e "${YELLOW}UFW规则已删除: $port/$proto${NC}"
            ;;
    esac
}

# 同步UFW规则
sync_ufw_rules() {
    echo -e "${YELLOW}正在同步UFW规则...${NC}"
    declare -A active_ports
    local port proto
    
    # 收集当前规则中的端口
    for cmd in iptables ip6tables; do
        $cmd -t nat -S | grep "$SCRIPT_TAG" | while read -r rule; do
            if [[ $rule =~ --dport[[:space:]]+([0-9]+)(:([0-9]+))? ]]; then
                if [ -n "${BASH_REMATCH[3]}" ]; then
                    # 端口段
                    for ((p=${BASH_REMATCH[1]}; p<=${BASH_REMATCH[3]}; p++)); do
                        proto=$(grep -oP '(?<=-p )\w+' <<< "$rule")
                        active_ports["$p/$proto"]=1
                    done
                else
                    # 单端口
                    proto=$(grep -oP '(?<=-p )\w+' <<< "$rule")
                    active_ports["${BASH_REMATCH[1]}/$proto"]=1
                fi
            fi
        done
    done

    # 删除不存在的UFW规则
    ufw status numbered | grep "$SCRIPT_TAG" | while read line; do
        port_proto=$(awk '{print $2}' <<< "$line" | cut -d'/' -f1,2)
        [[ ! "${!active_ports[@]}" =~ "$port_proto" ]] && {
            rule_num=$(awk -F'[][]' '{print $2}' <<< "$line")
            yes | ufw delete $rule_num >/dev/null
            echo -e "${YELLOW}删除过期UFW规则: $port_proto${NC}"
        }
    done

    # 添加缺失的UFW规则
    for port_proto in "${!active_ports[@]}"; do
        ufw status | grep -q "$port_proto.*$SCRIPT_TAG" || {
            port=${port_proto%/*}
            proto=${port_proto#*/}
            manage_ufw_rule add $port $proto
        }
    done
    echo -e "${GREEN}UFW规则同步完成${NC}"
}

# 规则管理核心
manage_rules() {
    local action=$1
    for cmd in iptables ip6tables; do
        for table in nat filter; do
            $cmd -t $table -S | grep "$SCRIPT_TAG" | while read -r line; do
                if [ "$action" = "delete" ]; then
                    # 删除时提取端口和协议
                    if [[ $line =~ --dport[[:space:]]+([0-9]+) ]]; then
                        port=${BASH_REMATCH[1]}
                        proto=$(grep -oP '(?<=-p )\w+' <<< "$line")
                        manage_ufw_rule del $port $proto 2>/dev/null
                    fi
                    $cmd -t $table ${line/-A/-D}
                else
                    echo "$cmd -t $table ${line#-A }"
                fi
            done
        done
    done
}

# 保存规则
save_rules() {
    echo "#!/bin/bash" > "$RULES_FILE"
    echo "# 自动生成的端口转发规则" >> "$RULES_FILE"
    echo "SCRIPT_TAG=\"$SCRIPT_TAG\"" >> "$RULES_FILE"
    echo "NAT64_PREFIX=\"$NAT64_PREFIX\"" >> "$RULES_FILE"
    echo >> "$RULES_FILE"
    
    # 系统配置
    echo "# 系统配置" >> "$RULES_FILE"
    echo "sysctl -w net.ipv4.ip_forward=1" >> "$RULES_FILE"
    echo "sysctl -w net.ipv6.conf.all.forwarding=1" >> "$RULES_FILE"
    echo "ip -6 route add local ${NAT64_PREFIX}/96 dev lo 2>/dev/null" >> "$RULES_FILE"
    echo >> "$RULES_FILE"
    
    # 规则配置
    echo "# 转发规则" >> "$RULES_FILE"
    manage_rules save >> "$RULES_FILE"
    
    chmod +x "$RULES_FILE"
    systemctl daemon-reload
    systemctl enable portforward.service >/dev/null 2>&1
}

# 添加单端口转发
add_single_port_forward() {
    get_listen_ip
    read -p "请输入本机监听端口: " LOCAL_PORT
    read -p "请输入目标服务器IP: " TARGET_IP
    read -p "请输入目标服务器端口: " TARGET_PORT

    select_protocol

    # 处理监听模式
    case $LISTEN_IP in
        "dual") 
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN="[::]"
            ;;
        "0.0.0.0") 
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN=""
            ;;
        *) 
            if is_ipv4 "$LISTEN_IP"; then
                IPV4_LISTEN="$LISTEN_IP"
                IPV6_LISTEN=""
            elif is_ipv6 "$LISTEN_IP"; then
                IPV4_LISTEN=""
                IPV6_LISTEN="$LISTEN_IP"
            else
                echo -e "${RED}无效的监听地址${NC}"; return 1
            fi
            ;;
    esac

    # 添加规则
    for PROTO in "${PROTOS[@]}"; do
        # IPv4规则
        [ -n "$IPV4_LISTEN" ] && {
            if is_ipv6 "$TARGET_IP"; then
                TARGET_ADDR="[$TARGET_IP]"
                echo -e "${YELLOW}配置NAT46转发: IPv4->IPv6${NC}"
            else
                TARGET_ADDR="$TARGET_IP"
            fi
            
            iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_PORT \
                -m comment --comment "$SCRIPT_TAG"
                
            iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            iptables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
                
            manage_ufw_rule add $LOCAL_PORT $PROTO
        }

        # IPv6规则
        [ -n "$IPV6_LISTEN" ] && has_usable_ipv6 && {
            if is_ipv4 "$TARGET_IP"; then
                TARGET_ADDR=$(ipv4_to_nat64 "$TARGET_IP")
                echo -e "${YELLOW}配置NAT64转发: IPv6->IPv4${NC}"
                manage_nat64
            else
                TARGET_ADDR="[$TARGET_IP]"
            fi
            
            ip6tables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_PORT \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_PORT \
                -m comment --comment "$SCRIPT_TAG"
                
            ip6tables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            ip6tables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_PORT \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
        }
    done

    save_rules
    echo -e "${GREEN}✅ 端口转发已添加:${NC}"
    [ -n "$IPV4_LISTEN" ] && echo -e "  IPv4: $IPV4_LISTEN:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT"
    [ -n "$IPV6_LISTEN" ] && echo -e "  IPv6: $IPV6_LISTEN:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT"
    echo -e "  协议: ${PROTOS[*]}"
}

# 添加端口段转发
add_port_range_forward() {
    get_listen_ip
    read -p "请输入本机起始端口: " LOCAL_START
    read -p "请输入本机结束端口: " LOCAL_END
    read -p "请输入目标服务器IP: " TARGET_IP
    read -p "请输入目标起始端口: " TARGET_START

    select_protocol

    # 计算端口数量
    local PORT_COUNT=$((LOCAL_END - LOCAL_START + 1))
    local TARGET_END=$((TARGET_START + PORT_COUNT - 1))

    # 处理监听模式
    case $LISTEN_IP in
        "dual") 
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN="[::]"
            ;;
        "0.0.0.0") 
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN=""
            ;;
        *) 
            if is_ipv4 "$LISTEN_IP"; then
                IPV4_LISTEN="$LISTEN_IP"
                IPV6_LISTEN=""
            elif is_ipv6 "$LISTEN_IP"; then
                IPV4_LISTEN=""
                IPV6_LISTEN="$LISTEN_IP"
            else
                echo -e "${RED}无效的监听地址${NC}"; return 1
            fi
            ;;
    esac

    # 添加规则
    for PROTO in "${PROTOS[@]}"; do
        # IPv4规则
        [ -n "$IPV4_LISTEN" ] && {
            if is_ipv6 "$TARGET_IP"; then
                TARGET_ADDR="[$TARGET_IP]"
                echo -e "${YELLOW}配置NAT46转发: IPv4->IPv6${NC}"
            else
                TARGET_ADDR="$TARGET_IP"
            fi
            
            iptables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_START-$TARGET_END \
                -m comment --comment "$SCRIPT_TAG"
                
            iptables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR --dport $TARGET_START:$TARGET_END \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            iptables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_START:$TARGET_END \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
                
            # 添加UFW规则
            for ((port=LOCAL_START; port<=LOCAL_END; port++)); do
                manage_ufw_rule add $port $PROTO
            done
        }

        # IPv6规则
        [ -n "$IPV6_LISTEN" ] && has_usable_ipv6 && {
            if is_ipv4 "$TARGET_IP"; then
                TARGET_ADDR=$(ipv4_to_nat64 "$TARGET_IP")
                echo -e "${YELLOW}配置NAT64转发: IPv6->IPv4${NC}"
                manage_nat64
            else
                TARGET_ADDR="[$TARGET_IP]"
            fi
            
            ip6tables -t nat -A PREROUTING -p $PROTO --dport $LOCAL_START:$LOCAL_END \
                -j DNAT --to-destination $TARGET_ADDR:$TARGET_START-$TARGET_END \
                -m comment --comment "$SCRIPT_TAG"
                
            ip6tables -t nat -A POSTROUTING -p $PROTO -d $TARGET_ADDR --dport $TARGET_START:$TARGET_END \
                -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
                
            ip6tables -A FORWARD -p $PROTO -d $TARGET_ADDR --dport $TARGET_START:$TARGET_END \
                -j ACCEPT -m comment --comment "$SCRIPT_TAG"
        }
    done

    save_rules
    echo -e "${GREEN}✅ 端口段转发已添加:${NC}"
    [ -n "$IPV4_LISTEN" ] && echo -e "  IPv4: $IPV4_LISTEN:$LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-$TARGET_END"
    [ -n "$IPV6_LISTEN" ] && echo -e "  IPv6: $IPV6_LISTEN:$LOCAL_START-$LOCAL_END → $TARGET_IP:$TARGET_START-$TARGET_END"
    echo -e "  协议: ${PROTOS[*]}"
}

# 删除指定规则
delete_specific_rule() {
    echo -e "${YELLOW}当前转发规则:${NC}"
    local rules=() i=1
    while read -r line; do
        rules+=("$line")
        echo "$i. $line"
        ((i++))
    done < <(manage_rules list | sed 's/^-[AI] //')

    [ ${#rules[@]} -eq 0 ] && { echo -e "${RED}没有找到规则${NC}"; return; }

    read -p "请输入要删除的规则编号: " num
    [[ $num =~ ^[0-9]+$ ]] && [ $num -gt 0 ] && [ $num -le ${#rules[@]} ] || {
        echo -e "${RED}无效输入${NC}"; return;
    }

    local rule="${rules[$((num-1))]}"
    if [[ $rule =~ --dport[[:space:]]+([0-9]+) ]]; then
        local port=${BASH_REMATCH[1]}
        local proto=$(grep -oP '(?<=-p )\w+' <<< "$rule")
        manage_ufw_rule del $port $proto
    fi

    eval "$(sed 's/^/-D /' <<< "$rule")" && \
    echo -e "${GREEN}规则已删除${NC}" || \
    echo -e "${RED}删除失败${NC}"
}

# 主菜单
show_menu() {
    echo -e "\n${GREEN}===== 端口转发管理工具 =====${NC}"
    echo "1. 添加单个端口转发"
    echo "2. 添加端口段转发"
    echo "3. 删除指定规则"
    echo "4. 查看当前规则"
    echo "5. 同步UFW规则"
    echo "6. 清空所有规则"
    echo "0. 退出"
    echo -e "${GREEN}============================${NC}"
}

# 初始化
check_root
install_dependencies
manage_nat64
sysctl -w net.ipv4.ip_forward=1 >/dev/null
has_usable_ipv6 && sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

# 主循环
while true; do
    show_menu
    read -p "请选择操作: " choice
    case $choice in
        1) add_single_port_forward ;;
        2) add_port_range_forward ;;
        3) delete_specific_rule ;;
        4) manage_rules list | less ;;
        5) sync_ufw_rules ;;
        6) manage_rules delete; rm -f "$RULES_FILE" "$SERVICE_FILE" ;;
        0) echo -e "${GREEN}退出脚本${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
    echo
done