#!/bin/bash
# ============================================================
#   Backhaul Multi-Tunnel Manager (Free)
#   Run MULTIPLE tunnels on one server (each with own name/port)
# ============================================================

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'
case "$(uname -m)" in aarch64|arm64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
DL="https://github.com/Musixal/Backhaul/releases/download/v0.7.2/backhaul_linux_${ARCH}.tar.gz"
DIR="/root/backhaul-free"

[ "$(id -u)" -eq 0 ] || { echo -e "${R}Run as root${N}"; exit 1; }

enable_bbr() {
    grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null || {
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    }
    sysctl -p >/dev/null 2>&1
    echo -e "${G}    BBR: $(sysctl -n net.ipv4.tcp_congestion_control)${N}"
}

download_bin() {
    mkdir -p "$DIR"
    if [ ! -f "$DIR/backhaul" ]; then
        echo -e "${C}[+] Downloading...${N}"
        cd /root && wget -q "$DL" -O bh.tar.gz && tar -xzf bh.tar.gz -C "$DIR" && rm -f bh.tar.gz && chmod +x "$DIR/backhaul"
    fi
    [ -f "$DIR/backhaul" ] && echo -e "${G}    Binary ready${N}" || { echo -e "${R}Download failed${N}"; exit 1; }
}

save_fw() {
    iptables -I INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null
    command -v netfilter-persistent >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    echo -e "${G}    Firewall $1 opened (persistent)${N}"
}

new_iran() {
    echo -e "${C}=== New IRAN Tunnel ===${N}"
    echo -ne "${Y}Tunnel name (e.g. de1, fr2): ${N}"; read name
    [ -z "$name" ] && { echo -e "${R}Name required${N}"; return; }
    echo -ne "${Y}Tunnel port (unique, NOT an inbound port! e.g. 3080, 3081): ${N}"; read tport
    deftok=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
    echo -ne "${Y}Token (Enter = random ${deftok}): ${N}"; read token; token=${token:-$deftok}
    echo -ne "${Y}Service port(s) (e.g. 2020 or 2020,5050): ${N}"; read ports
    echo -ne "${Y}Transport (default tcpmux): ${N}"; read tr; tr=${tr:-tcpmux}

    enable_bbr; download_bin

    plist=""; IFS=',' read -ra P <<< "$ports"
    for p in "${P[@]}"; do plist="$plist    \"$(echo $p|xargs)\",\n"; done

    cfg="$DIR/iran-${name}.toml"
    cat > "$cfg" << EOF
[server]
bind_addr = "0.0.0.0:${tport}"
transport = "${tr}"
token = "${token}"
keepalive_period = 75
nodelay = true
heartbeat = 40
ports = [
$(echo -e "$plist")]
EOF
    cat > /etc/systemd/system/backhaul-${name}.service << EOF
[Unit]
After=network.target
[Service]
ExecStart=${DIR}/backhaul -c ${cfg}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now backhaul-${name} >/dev/null 2>&1
    systemctl restart backhaul-${name}
    save_fw "$tport"
    for p in "${P[@]}"; do save_fw "$(echo $p|xargs|cut -d= -f1|cut -d: -f1)"; done
    echo -e "${G}✅ IRAN tunnel '$name' created (port $tport)${N}"
    echo -e "${Y}    Token (kharej needs this): ${token}${N}"
    sleep 2; journalctl -u backhaul-${name} -n 5 --no-pager | cat
}

new_kharej() {
    echo -e "${C}=== New KHAREJ Tunnel ===${N}"
    echo -ne "${Y}Tunnel name (same idea, e.g. de1): ${N}"; read name
    [ -z "$name" ] && { echo -e "${R}Name required${N}"; return; }
    echo -ne "${Y}IRAN server IP: ${N}"; read iranip
    echo -ne "${Y}Tunnel port (same as iran side): ${N}"; read tport
    echo -ne "${Y}Token (same as iran side): ${N}"; read token
    [ -z "$token" ] && { echo -e "${R}Token required${N}"; return; }
    echo -ne "${Y}Transport (default tcpmux): ${N}"; read tr; tr=${tr:-tcpmux}

    enable_bbr; download_bin

    cfg="$DIR/kharej-${name}.toml"
    cat > "$cfg" << EOF
[client]
remote_addr = "${iranip}:${tport}"
transport = "${tr}"
token = "${token}"
connection_pool = 8
keepalive_period = 75
dial_timeout = 10
retry_interval = 3
nodelay = true
EOF
    cat > /etc/systemd/system/backhaul-${name}.service << EOF
[Unit]
After=network.target
[Service]
ExecStart=${DIR}/backhaul -c ${cfg}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now backhaul-${name} >/dev/null 2>&1
    systemctl restart backhaul-${name}
    echo -e "${G}✅ KHAREJ tunnel '$name' -> ${iranip}:${tport}${N}"
    sleep 3; journalctl -u backhaul-${name} -n 5 --no-pager | cat
}

list_tunnels() {
    echo -e "${C}--- All Backhaul Tunnels ---${N}"
    for svc in $(systemctl list-unit-files 2>/dev/null | grep -oE 'backhaul-[a-zA-Z0-9]+' | sort -u); do
        state=$(systemctl is-active $svc 2>/dev/null)
        [ "$state" = "active" ] && echo -e "  $svc: ${G}ACTIVE ✅${N}" || echo -e "  $svc: ${R}$state ❌${N}"
    done
}

del_tunnel() {
    list_tunnels
    echo -ne "${Y}Tunnel name to DELETE (e.g. de1): ${N}"; read name
    [ -z "$name" ] && return
    systemctl stop backhaul-${name} 2>/dev/null
    systemctl disable backhaul-${name} 2>/dev/null
    rm -f /etc/systemd/system/backhaul-${name}.service
    rm -f "$DIR/iran-${name}.toml" "$DIR/kharej-${name}.toml"
    systemctl daemon-reload
    echo -e "${G}Tunnel '$name' deleted${N}"
}

while true; do
    clear
    echo -e "${C}============================================${N}"
    echo -e "${C}   Backhaul MULTI-Tunnel Manager${N}"
    echo -e "${C}============================================${N}"
    echo ""
    echo "  1. New IRAN tunnel   (on IRAN server)"
    echo "  2. New KHAREJ tunnel (on FOREIGN server)"
    echo "  3. List all tunnels"
    echo "  4. Delete a tunnel"
    echo "  5. Restart a tunnel"
    echo "  0. Exit"
    echo ""
    echo -ne "${Y}Choice: ${N}"; read ch; echo ""
    case $ch in
        1) new_iran ;;
        2) new_kharej ;;
        3) list_tunnels ;;
        4) del_tunnel ;;
        5) echo -ne "${Y}Tunnel name: ${N}"; read n; systemctl restart backhaul-${n} && echo -e "${G}Restarted${N}" ;;
        0) exit 0 ;;
        *) echo -e "${R}Invalid${N}" ;;
    esac
    echo ""; echo -ne "${Y}Press Enter...${N}"; read
done
