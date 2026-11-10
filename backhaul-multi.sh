Claude





















Backhaul multi · SH
#!/bin/bash
# ============================================================
#   Backhaul Multi-Tunnel Manager (Free)
#   Run MULTIPLE tunnels on one server (each with own name/port)
#   After first run, just type:  bh
# ============================================================
 
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'
URL="https://raw.githubusercontent.com/knokjadgal-glitch/tunnel/main/backhaul-multi.sh"
VER="v0.7.2"
case "$(uname -m)" in aarch64|arm64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
DL="https://github.com/Musixal/Backhaul/releases/download/${VER}/backhaul_linux_${ARCH}.tar.gz"
DIR="/root/backhaul-free"
 
[ "$(id -u)" -eq 0 ] || { echo -e "${R}Run as root${N}"; exit 1; }
 
# ---------- self install as "bh" ----------
if [ "$(readlink -f "$0")" != "/usr/local/bin/bh" ]; then
    curl -fsSL "$URL" -o /usr/local/bin/bh 2>/dev/null && chmod +x /usr/local/bin/bh \
        && echo -e "${G}Installed! From now on just type: bh${N}" && sleep 2
fi
 
pause() { echo ""; echo -ne "${Y}Press Enter...${N}"; read; }
 
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
        cd /root && curl -fsSL "$DL" -o bh.tar.gz && tar -xzf bh.tar.gz -C "$DIR" && rm -f bh.tar.gz && chmod +x "$DIR/backhaul"
    fi
    [ -f "$DIR/backhaul" ] && echo -e "${G}    Binary ready${N}" || { echo -e "${R}Download failed${N}"; exit 1; }
}
 
save_fw() {
    [ -z "$1" ] && return
    iptables -C INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null
    command -v ufw >/dev/null 2>&1 && ufw allow "$1"/tcp >/dev/null 2>&1
    command -v netfilter-persistent >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    echo -e "${G}    Firewall $1 opened${N}"
}
 
write_service() {   # $1=name  $2=cfg
    cat > /etc/systemd/system/backhaul-$1.service << EOF
[Unit]
After=network.target
[Service]
ExecStart=${DIR}/backhaul -c $2
Restart=always
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now backhaul-$1 >/dev/null 2>&1
    systemctl restart backhaul-$1
}
 
ports_to_toml() {   # "2020,5050" -> toml lines
    local out="" p
    IFS=',' read -ra PP <<< "$1"
    for p in "${PP[@]}"; do p=$(echo "$p" | xargs); [ -n "$p" ] && out="$out    \"$p\",\n"; done
    echo -e "$out"
}
 
# ---------------- create ----------------
new_iran() {
    echo -e "${C}=== New IRAN Tunnel ===${N}"
    echo -ne "${Y}Tunnel name (e.g. de1, fr2): ${N}"; read name
    [ -z "$name" ] && { echo -e "${R}Name required${N}"; return; }
    [ -f "$DIR/iran-${name}.toml" ] && { echo -e "${R}This name already exists${N}"; return; }
    echo -ne "${Y}Tunnel port (unique, NOT an inbound port! e.g. 3080, 3081): ${N}"; read tport
    deftok=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
    echo -ne "${Y}Token (Enter = random ${deftok}): ${N}"; read token; token=${token:-$deftok}
    echo -ne "${Y}Forward port(s) (e.g. 2020 or 2020,5050): ${N}"; read ports
    echo -ne "${Y}Transport [tcp/tcpmux/ws/wsmux/udp] (default tcpmux): ${N}"; read tr; tr=${tr:-tcpmux}
 
    enable_bbr; download_bin
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
$(ports_to_toml "$ports")]
EOF
    write_service "$name" "$cfg"
    save_fw "$tport"
    IFS=',' read -ra P <<< "$ports"
    for p in "${P[@]}"; do save_fw "$(echo $p | xargs | cut -d= -f1 | cut -d: -f1)"; done
    echo -e "${G}✅ IRAN tunnel '$name' created (port $tport)${N}"
    echo -e "${Y}    Token (kharej needs this): ${token}${N}"
    sleep 2; journalctl -u backhaul-${name} -n 5 --no-pager | cat
}
 
new_kharej() {
    echo -e "${C}=== New KHAREJ Tunnel ===${N}"
    echo -ne "${Y}Tunnel name (e.g. de1): ${N}"; read name
    [ -z "$name" ] && { echo -e "${R}Name required${N}"; return; }
    [ -f "$DIR/kharej-${name}.toml" ] && { echo -e "${R}This name already exists${N}"; return; }
    echo -ne "${Y}IRAN server IP: ${N}"; read iranip
    echo -ne "${Y}Tunnel port (same as iran side): ${N}"; read tport
    echo -ne "${Y}Token (same as iran side): ${N}"; read token
    [ -z "$token" ] && { echo -e "${R}Token required${N}"; return; }
    echo -ne "${Y}Transport (same as iran side, default tcpmux): ${N}"; read tr; tr=${tr:-tcpmux}
 
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
    write_service "$name" "$cfg"
    echo -e "${G}✅ KHAREJ tunnel '$name' -> ${iranip}:${tport}${N}"
    sleep 3; journalctl -u backhaul-${name} -n 5 --no-pager | cat
}
 
# ---------------- helpers for editing ----------------
get_val() { grep -E "^$2 *=" "$1" | head -1 | cut -d'"' -f2; }          # file key
set_val() { sed -i -E "s|^($2 *= *\").*(\")|\1$3\2|" "$1"; }            # file key value
get_ports() { sed -n '/^ports *= *\[/,/\]/p' "$1" | grep -oE '"[^"]+"' | tr -d '"' | paste -sd, -; }
 
# fills arrays NAMES[] ROLES[] CFGS[]
collect() {
    NAMES=(); ROLES=(); CFGS=()
    for f in "$DIR"/iran-*.toml "$DIR"/kharej-*.toml; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .toml)
        NAMES+=("${b#*-}"); ROLES+=("${b%%-*}"); CFGS+=("$f")
    done
}
 
list_tunnels() {
    collect
    echo -e "${C}--- All Backhaul Tunnels ---${N}"
    [ ${#NAMES[@]} -eq 0 ] && { echo "  (no tunnels)"; return 1; }
    for i in "${!NAMES[@]}"; do
        n=${NAMES[$i]}; f=${CFGS[$i]}
        state=$(systemctl is-active backhaul-$n 2>/dev/null)
        [ "$state" = "active" ] && st="${G}ACTIVE ✅${N}" || st="${R}$state ❌${N}"
        if [ "${ROLES[$i]}" = "iran" ]; then
            info="IRAN   port $(get_val "$f" bind_addr | awk -F: '{print $NF}')  fwd [$(get_ports "$f")]  $(get_val "$f" transport)"
        else
            info="KHAREJ -> $(get_val "$f" remote_addr)  $(get_val "$f" transport)"
        fi
        echo -e "  $((i+1)). ${Y}$n${N}  $info  $st"
    done
    return 0
}
 
apply_restart() { systemctl restart backhaul-$1 && echo -e "${G}✅ Saved & restarted${N}"; }
 
# ---------------- tunnel submenu ----------------
manage_tunnel() {
    list_tunnels || return
    echo ""; echo -ne "${Y}Select tunnel number: ${N}"; read num
    idx=$((num-1))
    [ -z "${NAMES[$idx]}" ] && { echo -e "${R}Invalid${N}"; return; }
    n=${NAMES[$idx]}; role=${ROLES[$idx]}; f=${CFGS[$idx]}
 
    while true; do
        clear
        echo -e "${C}=== Tunnel: ${Y}$n${C} ($role) ===${N}"
        echo -e "  Status: $(systemctl is-active backhaul-$n)"
        if [ "$role" = "iran" ]; then
            echo "  Tunnel port : $(get_val "$f" bind_addr | awk -F: '{print $NF}')"
            echo "  Forward     : $(get_ports "$f")"
        else
            echo "  Iran IP     : $(get_val "$f" remote_addr | cut -d: -f1)"
            echo "  Tunnel port : $(get_val "$f" remote_addr | awk -F: '{print $NF}')"
        fi
        echo "  Transport   : $(get_val "$f" transport)"
        echo ""
        echo "  1. Edit IRAN IP          (kharej side)"
        echo "  2. Edit tunnel port"
        echo "  3. Edit forward ports    (iran side)"
        echo "  4. Edit token"
        echo "  5. Edit transport"
        echo "  6. Show config"
        echo "  7. Show logs"
        echo "  8. Restart"
        echo "  9. Stop / Start"
        echo " 10. Delete this tunnel"
        echo "  0. Back"
        echo ""
        echo -ne "${Y}Choice: ${N}"; read c; echo ""
        case $c in
            1)
                if [ "$role" != "kharej" ]; then
                    echo -e "${Y}On the IRAN side the foreign IP is not stored.${N}"
                    echo -e "${Y}Kharej connects to Iran, so edit the IRAN IP on the KHAREJ server.${N}"
                else
                    port=$(get_val "$f" remote_addr | awk -F: '{print $NF}')
                    echo -ne "${Y}New IRAN IP: ${N}"; read v
                    [ -n "$v" ] && set_val "$f" remote_addr "$v:$port" && apply_restart "$n"
                fi ;;
            2)
                echo -e "${Y}Remember: change it on BOTH servers (same value).${N}"
                echo -ne "${Y}New tunnel port: ${N}"; read v
                [ -z "$v" ] && { pause; continue; }
                if [ "$role" = "iran" ]; then
                    set_val "$f" bind_addr "0.0.0.0:$v"; save_fw "$v"
                else
                    ip=$(get_val "$f" remote_addr | cut -d: -f1)
                    set_val "$f" remote_addr "$ip:$v"
                fi
                apply_restart "$n" ;;
            3)
                if [ "$role" != "iran" ]; then
                    echo -e "${Y}Forward ports are set on the IRAN server.${N}"
                else
                    echo "Current: $(get_ports "$f")"
                    echo -ne "${Y}New forward port(s) (e.g. 2020,5050): ${N}"; read v
                    if [ -n "$v" ]; then
                        tmp=$(mktemp)
                        awk -v new="$(ports_to_toml "$v")" '
                            /^ports *= *\[/ {print "ports = ["; printf "%s\n", new; print "]"; skip=1; next}
                            skip && /\]/ {skip=0; next}
                            !skip {print}' "$f" > "$tmp" && mv "$tmp" "$f"
                        IFS=',' read -ra P <<< "$v"
                        for p in "${P[@]}"; do save_fw "$(echo $p | xargs | cut -d= -f1 | cut -d: -f1)"; done
                        apply_restart "$n"
                    fi
                fi ;;
            4)
                echo -e "${Y}Remember: change it on BOTH servers (same value).${N}"
                echo -ne "${Y}New token: ${N}"; read v
                [ -n "$v" ] && set_val "$f" token "$v" && apply_restart "$n" ;;
            5)
                echo -e "${Y}Remember: change it on BOTH servers (same value).${N}"
                echo -ne "${Y}New transport [tcp/tcpmux/ws/wsmux/udp]: ${N}"; read v
                [ -n "$v" ] && set_val "$f" transport "$v" && apply_restart "$n" ;;
            6) cat "$f" ;;
            7) journalctl -u backhaul-$n -n 30 --no-pager | cat ;;
            8) apply_restart "$n" ;;
            9)
                if systemctl is-active --quiet backhaul-$n; then
                    systemctl stop backhaul-$n && echo -e "${Y}Stopped${N}"
                else
                    systemctl start backhaul-$n && echo -e "${G}Started${N}"
                fi ;;
            10)
                echo -ne "${R}Delete '$n'? (y/N): ${N}"; read y
                if [ "$y" = "y" ]; then
                    systemctl disable --now backhaul-$n >/dev/null 2>&1
                    rm -f /etc/systemd/system/backhaul-$n.service "$f"
                    systemctl daemon-reload
                    echo -e "${G}Tunnel '$n' deleted${N}"; pause; return
                fi ;;
            0) return ;;
            *) echo -e "${R}Invalid${N}" ;;
        esac
        pause
    done
}
 
update_script() {
    curl -fsSL "$URL" -o /usr/local/bin/bh && chmod +x /usr/local/bin/bh \
        && echo -e "${G}Updated. Run: bh${N}" && exit 0
    echo -e "${R}Update failed${N}"
}
 
uninstall_all() {
    echo -ne "${R}Remove ALL tunnels and bh? (y/N): ${N}"; read y
    [ "$y" != "y" ] && return
    collect
    for n in "${NAMES[@]}"; do
        systemctl disable --now backhaul-$n >/dev/null 2>&1
        rm -f /etc/systemd/system/backhaul-$n.service
    done
    systemctl daemon-reload
    rm -rf "$DIR" /usr/local/bin/bh
    echo -e "${G}Everything removed${N}"; exit 0
}
 
# ---------------- main menu ----------------
while true; do
    clear
    echo -e "${C}============================================${N}"
    echo -e "${C}   Backhaul MULTI-Tunnel Manager   (bh)${N}"
    echo -e "${C}============================================${N}"
    echo ""
    echo "  1. New IRAN tunnel   (on IRAN server)"
    echo "  2. New KHAREJ tunnel (on FOREIGN server)"
    echo "  3. List tunnels"
    echo "  4. Manage a tunnel   (edit / logs / delete)"
    echo "  5. Update this script"
    echo "  6. Uninstall everything"
    echo "  0. Exit"
    echo ""
    echo -ne "${Y}Choice: ${N}"; read ch; echo ""
    case $ch in
        1) new_iran; pause ;;
        2) new_kharej; pause ;;
        3) list_tunnels; pause ;;
        4) manage_tunnel ;;
        5) update_script; pause ;;
        6) uninstall_all; pause ;;
        0) exit 0 ;;
        *) echo -e "${R}Invalid${N}"; pause ;;
    esac
done
 
