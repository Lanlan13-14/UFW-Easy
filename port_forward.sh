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
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误：此脚本必须以root权限运行${NC}" >&2
        exit 1
    fi
}

# 安装必要依赖
install_dependencies() {
    echo -e "${YELLOW}正在检查系统依赖...${NC}"
    if command -v apt >/dev/null; then
        apt update
        apt install -y curl iptables ip6tables ufw kmod git make gcc
    elif command -v yum >/dev/null; then
        yum install -y curl iptables ip6tables ufw kernel-devel git make gcc
    else
        echo -e "${RED}不支持的包管理器，请手动安装依赖${NC}"
        return 1
    fi
}

# 检测并安装NAT64/NAT46模块
install_nat64_module() {
    if ! lsmod | grep -q "nat46" && has_usable_ipv6; then
        echo -e "${YELLOW}正在安装NAT64/NAT46支持...${NC}"
        
        # 检查内核头文件
        if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
            echo -e "${RED}未找到内核头文件，请先安装:${NC}"
            if command -v apt >/dev/null; then
                echo "apt install linux-headers-$(uname -r)"
            else
                echo "yum install kernel-devel-$(uname -r)"
            fi
            return 1
        fi

        # 从GitHub克隆nat46项目
        if [ ! -d "/tmp/nat46" ]; then
            git clone https://github.com/ayourtch/nat46.git /tmp/nat46 || {
                echo -e "${RED}无法克隆nat46仓库${NC}"
                return 1
            }
        fi

        # 编译安装
        cd /tmp/nat46 || return 1
        make && make install || {
            echo -e "${RED}nat46模块编译失败${NC}"
            return 1
        }

        # 加载模块
        if ! modprobe nat46; then
            echo -e "${RED}无法加载nat46模块${NC}"
            return 1
        fi

        # 持久化模块加载
        if ! grep -q "nat46" /etc/modules-load.d/nat46.conf 2>/dev/null; then
            echo "nat46" > /etc/modules-load.d/nat46.conf
        fi

        echo -e "${GREEN}NAT64/NAT46模块安装成功${NC}"
    fi
}

# 配置NAT64网络
setup_nat64_network() {
    if ! ip -6 route show | grep -q "${NAT64_PREFIX}/96"; then
        ip -6 route add local ${NAT64_PREFIX}/96 dev lo
        echo -e "${GREEN}已添加NAT64本地路由${NC}"
    fi

    if ! ip6tables -t nat -L POSTROUTING | grep -q "MASQUERADE.*NAT64"; then
        ip6tables -t nat -A POSTROUTING -s ${NAT64_PREFIX}/96 -j MASQUERADE -m comment --comment "NAT64"
        echo -e "${GREEN}已配置NAT64 MASQUERADE规则${NC}"
    fi
}

# 检测真实IPv6支持
has_usable_ipv6() {
    # 方法1: 测试实际网络连接
    if curl -s -6 --connect-timeout 3 https://ipv6.google.com >/dev/null 2>&1; then
        return 0
    fi
    
    # 方法2: 检查全局IPv6地址
    if ip -6 addr show scope global | grep -q 'inet6'; then
        return 0
    fi
    
    # 方法3: 检查内核支持
    [ -s /proc/net/if_inet6 ]
}

# 地址类型检测
is_ipv4() {
    [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

is_ipv6() {
    [[ $1 =~ : ]]
}

# IPv4转NAT64格式
ipv4_to_nat64() {
    local ipv4=$1
    echo "${NAT64_PREFIX}$(echo $ipv4 | sed 's/\./:/g')"
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
        *) echo -e "${RED}无效选择，默认使用TCP${NC}"; PROTOS=("tcp") ;;
    esac
}

# 获取监听IP
get_listen_ip() {
    read -p "请输入监听IP (回车自动选择): " LISTEN_IP
    
    if [ -z "$LISTEN_IP" ]; then
        if has_usable_ipv6; then
            LISTEN_IP="dual"
            echo -e "${GREEN}自动选择: 双栈监听 (IPv4+IPv6)${NC}"
        else
            LISTEN_IP="0.0.0.0"
            echo -e "${GREEN}自动选择: IPv4 (0.0.0.0)${NC}"
        fi
    else
        if is_ipv6 "$LISTEN_IP" && [[ ! "$LISTEN_IP" =~ ^\[.*\]$ ]]; then
            LISTEN_IP="[$LISTEN_IP]"
        fi
    fi
}

# 添加UFW规则
add_ufw_rule() {
    local port=$1 proto=$2
    if ! ufw status | grep -q "$port/$proto.*$SCRIPT_TAG"; then
        ufw allow $port/$proto comment "$SCRIPT_TAG" >/dev/null 2>&1 && \
        echo -e "${GREEN}已添加UFW规则: $port/$proto${NC}"
    fi
}

# 删除UFW规则
del_ufw_rule() {
    local port=$1 proto=$2
    ufw delete allow $port/$proto >/dev/null 2>&1
}

# 清除所有iptables规则
clear_all_iptables_rules() {
    for cmd in iptables ip6tables; do
        for table in nat filter; do
            $cmd -t $table -S | grep "$SCRIPT_TAG" | while read -r line; do
                rule=$(echo "$line" | sed 's/-A/-D/')
                $cmd -t $table $rule
            done
        done
    done
    echo -e "${GREEN}已清除所有iptables/ip6tables规则${NC}"
}

# 创建systemd服务
enable_systemd_service() {
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Port Forwarding Service
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
    systemctl enable portforward.service >/dev/null 2>&1
    systemctl start portforward.service >/dev/null 2>&1
    echo -e "${GREEN}Systemd服务已配置${NC}"
}

# 保存规则到文件
save_rules_to_file() {
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
    for cmd in iptables ip6tables; do
        for table in nat filter; do
            $cmd -t $table -S | grep "$SCRIPT_TAG" | while read -r line; do
                echo "$cmd -t $table ${line#-A }" | sed 's/-A /-I /' >> "$RULES_FILE"
            done
        done
    done
    
    chmod +x "$RULES_FILE"
    enable_systemd_service
}

# 添加单端口转发
add_single_port_forward() {
    get_listen_ip
    read -p "请输入本机监听端口: " LOCAL_PORT
    read -p "请输入目标服务器IP: " TARGET_IP
    read -p "请输入目标服务器端口: " TARGET_PORT

    select_protocol

    clear_all_iptables_rules

    # 处理监听模式
    IPV4_LISTEN=""
    IPV6_LISTEN=""
    
    case $LISTEN_IP in
        "dual")
            IPV4_LISTEN="0.0.0.0"
            IPV6_LISTEN="[::]"
            echo -e "${YELLOW}配置双栈监听: IPv4($IPV4_LISTEN) + IPv6($IPV6_LISTEN)${NC}"
            ;;
        "0.0.0.0")
            IPV4_LISTEN="0.0.0.0"
            echo -e "${YELLOW}配置IPv4监听: $IPV4_LISTEN${NC}"
            ;;
        *)
            if is_ipv4 "$LISTEN_IP"; then
                IPV4_LISTEN="$LISTEN_IP"
                echo -e "${YELLOW}配置IPv4监听: $IPV4_LISTEN${NC}"
            elif is_ipv6 "$LISTEN_IP"; then
                IPV6_LISTEN="$LISTEN_IP"
                echo -e "${YELLOW}配置IPv6监听: $IPV6_LISTEN${NC}"
            else
                echo -e "${RED}无效的监听地址: $LISTEN_IP${NC}"
                return 1
            fi
            ;;
    esac

    # 添加规则
    for PROTO in "${PROTOS[@]}"; do
        # IPv4规则
        if [ -n "$IPV4_LISTEN" ]; then
            # 目标地址处理
            if is_ipv6 "$TARGET_IP"; then
                echo -e "${YELLOW}配置NAT46转发: IPv4->IPv6${NC}"
                TARGET_ADDR="[$TARGET_IP]"
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
                
            add_ufw_rule "$LOCAL_PORT" "$PROTO"
        fi

        # IPv6规则
        if [ -n "$IPV6_LISTEN" ] && has_usable_ipv6; then
            # 目标地址处理
            if is_ipv4 "$TARGET_IP"; then
                echo -e "${YELLOW}配置NAT64转发: IPv6->IPv4${NC}"
                install_nat64_module
                setup_nat64_network
                TARGET_ADDR=$(ipv4_to_nat64 "$TARGET_IP")
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
        fi
    done

    save_rules_to_file
    echo -e "${GREEN}✅ 端口转发已添加:${NC}"
    [ -n "$IPV4_LISTEN" ] && echo -e "  IPv4: $IPV4_LISTEN:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT"
    [ -n "$IPV6_LISTEN" ] && echo -e "  IPv6: $IPV6_LISTEN:$LOCAL_PORT → $TARGET_IP:$TARGET_PORT"
    echo -e "  协议: ${PROTOS[*]}"
}

# 查看规则
list_rules() {
    echo -e "${YELLOW}当前转发规则:${NC}"
    echo -e "${GREEN}IPv4 NAT表:${NC}"
    iptables -t nat -nL | grep -A 10 "$SCRIPT_TAG" || echo "无"
    echo -e "${GREEN}IPv6 NAT表:${NC}"
    ip6tables -t nat -nL | grep -A 10 "$SCRIPT_TAG" || echo "无"
}

# 删除所有规则
clear_all_rules() {
    clear_all_iptables_rules
    rm -f "$RULES_FILE" 2>/dev/null
    systemctl disable portforward.service >/dev/null 2>&1
    rm -f "$SERVICE_FILE" 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}所有配置已清除${NC}"
}

# 确保IP转发已启用
ensure_ip_forwarding() {
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf || \
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    
    if has_usable_ipv6; then
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
        grep -q '^net.ipv6.conf.all.forwarding' /etc/sysctl.conf || \
            echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
}

# 主菜单
show_menu() {
    echo -e "\n${GREEN}===== 端口转发管理工具 =====${NC}"
    echo "1. 添加单个端口转发"
    echo "2. 查看当前规则"
    echo "3. 删除所有规则"
    echo "0. 退出"
    echo -e "${GREEN}============================${NC}"
}

# 初始化
check_root
install_dependencies
ensure_ip_forwarding

# 主循环
while true; do
    show_menu
    read -p "请选择操作: " choice
    case $choice in
        1) add_single_port_forward ;;
        2) list_rules ;;
        3) clear_all_rules ;;
        0) echo -e "${GREEN}退出脚本${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
    echo
done