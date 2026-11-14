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
    apply_turbo_cfg "$cfg"; tune_kernel
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
    apply_turbo_cfg "$cfg"; tune_kernel
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
 
# ---------------- turbo (speed optimization) ----------------
# Values used for every tunnel created by this script (tcp / tcpmux get the socket tuning).
TURBO_SERVER='nodelay = true
channel_size = 4096
so_rcvbuf = 8388608
so_sndbuf = 8388608
mss = 1360
log_level = "warn"'
TURBO_CLIENT='nodelay = true
connection_pool = 32
aggressive_pool = true
so_rcvbuf = 8388608
so_sndbuf = 8388608
mss = 1360
log_level = "warn"'
 
set_key() {   # file key value  -> replace key if present, else insert right after the [server]/[client] line
    if grep -qE "^$2 *=" "$1"; then
        sed -i -E "s|^$2 *=.*|$2 = $3|" "$1"
    else
        sed -i -E "0,/^\[(server|client)\]/s||&\n$2 = $3|" "$1"
    fi
}
 
apply_turbo_cfg() {   # file
    local block
    grep -q '^\[server\]' "$1" && block="$TURBO_SERVER" || block="$TURBO_CLIENT"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        set_key "$1" "$(echo "${line%%=*}" | sed 's/^ *//;s/ *$//')" "$(echo "${line#*=}" | sed 's/^ *//;s/ *$//')"
    done <<< "$block"
}
 
tune_kernel() {
    cat > /etc/sysctl.d/99-bh-turbo.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 67108864
net.ipv4.tcp_wmem = 4096 1048576 67108864
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_syn_backlog = 65535
fs.file-max = 2097152
EOF
    modprobe tcp_bbr 2>/dev/null
    sysctl -p /etc/sysctl.d/99-bh-turbo.conf >/dev/null 2>&1
    echo -e "${G}    Kernel tuned (BBR: $(sysctl -n net.ipv4.tcp_congestion_control), big buffers)${N}"
}
 
turbo_all() {
    echo -e "${C}=== TURBO: optimize this server and all its tunnels ===${N}"
    tune_kernel
    collect
    [ ${#NAMES[@]} -eq 0 ] && { echo "  (no tunnels yet - new tunnels will be created with turbo settings)"; return; }
    for i in "${!NAMES[@]}"; do
        apply_turbo_cfg "${CFGS[$i]}"
        systemctl restart backhaul-${NAMES[$i]} && echo -e "${G}    ✅ ${NAMES[$i]} optimized & restarted${N}"
    done
    echo -e "${Y}Run TURBO on BOTH servers (Iran and Kharej) for the full effect.${N}"
}
 
# ---------------- transport speed test ----------------
# Runs temporary tunnels (one per transport) between the two servers,
# then measures latency and download speed through each one from the IRAN side.
TBASE=41000                       # tunnel ports 41000-41003, test ports 41100-41103, web 41200
TRANSPORTS=(tcp tcpmux ws wsmux)
TDIR=/root/bh-test
TPIDS=()
 
test_cleanup() {
    for p in "${TPIDS[@]}"; do kill "$p" 2>/dev/null; done
    TPIDS=()
    for i in "${!TRANSPORTS[@]}"; do
        iptables -D INPUT -p tcp --dport $((TBASE+i)) -j ACCEPT 2>/dev/null
    done
    rm -rf "$TDIR"
}
 
test_iran() {
    echo -e "${C}=== Transport test: IRAN side ===${N}"
    echo -e "${Y}Run this FIRST on the IRAN server, then 'Transport test: KHAREJ side' on the foreign server.${N}"
    deftok=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    echo -ne "${Y}Test token (Enter = ${deftok}): ${N}"; read token; token=${token:-$deftok}
    download_bin >/dev/null
    TDIR=/root/bh-test-iran; test_cleanup; mkdir -p "$TDIR"
    trap 'test_cleanup; exit 1' INT
    for i in "${!TRANSPORTS[@]}"; do
        cat > "$TDIR/s$i.toml" << EOF
[server]
bind_addr = "0.0.0.0:$((TBASE+i))"
transport = "${TRANSPORTS[$i]}"
token = "${token}"
keepalive_period = 75
nodelay = true
heartbeat = 40
ports = ["$((TBASE+100+i))=$((TBASE+200))"]
EOF
        apply_turbo_cfg "$TDIR/s$i.toml"
        "$DIR/backhaul" -c "$TDIR/s$i.toml" > "$TDIR/s$i.log" 2>&1 & TPIDS+=($!)
        iptables -I INPUT -p tcp --dport $((TBASE+i)) -j ACCEPT 2>/dev/null
    done
    myip=$(curl -s4 --max-time 5 ifconfig.me)
    echo ""
    echo -e "${G}Test servers are running.${N} Now on the KHAREJ server: ${Y}bh${N} -> ${Y}8${N}"
    echo -e "   IRAN IP : ${Y}${myip}${N}"
    echo -e "   Token   : ${Y}${token}${N}"
    echo ""
    echo -ne "${Y}When the KHAREJ side says 'READY', press Enter here...${N}"; read
    echo -e "${C}Waiting for tunnels to connect...${N}"; sleep 8
 
    printf "\n%-8s %-12s %-14s %s\n" "TRANSPORT" "LATENCY(ms)" "SPEED(MB/s)" "STATUS"
    printf -- "--------------------------------------------------\n"
    best=""; bestspd=0; bestlat=""; minlat=999999
    for i in "${!TRANSPORTS[@]}"; do
        t=${TRANSPORTS[$i]}; port=$((TBASE+100+i)); tot=0; ok=0
        for r in 1 2 3 4 5; do
            v=$(curl -s -o /dev/null -w '%{http_code} %{time_starttransfer}' --max-time 5 "http://127.0.0.1:$port/s" 2>/dev/null)
            [ "${v%% *}" = "200" ] && { tot=$(awk -v a="$tot" -v b="${v#* }" 'BEGIN{print a+b}'); ok=$((ok+1)); }
        done
        if [ "$ok" -eq 0 ]; then
            printf "%-8s %-12s %-14s ${R}%s${N}\n" "$t" "-" "-" "FAILED"; continue
        fi
        lat=$(awk -v a="$tot" -v n="$ok" 'BEGIN{printf "%.0f", a/n*1000}')
        spd=$(curl -s -o /dev/null -w '%{speed_download}' --max-time 15 "http://127.0.0.1:$port/big" 2>/dev/null)
        spd=$(awk -v s="${spd:-0}" 'BEGIN{printf "%.2f", s/1048576}')
        printf "%-8s %-12s %-14s ${G}%s${N}\n" "$t" "$lat" "$spd" "OK ($ok/5)"
        if awk -v a="$spd" -v b="$bestspd" 'BEGIN{exit !(a>b)}'; then best=$t; bestspd=$spd; fi
        if [ "$lat" -lt "$minlat" ]; then minlat=$lat; bestlat=$t; fi
    done
    echo ""
    if [ -n "$best" ]; then
        echo -e "${G}🚀 Fastest download : ${Y}$best${G} (${bestspd} MB/s)${N}"
        echo -e "${G}⚡ Lowest latency   : ${Y}$bestlat${G} (${minlat} ms)${N}"
        echo -e "${C}Tip: change a tunnel with  bh -> 4 -> select -> 5 (Edit transport)  on BOTH servers.${N}"
    else
        echo -e "${R}No transport worked. Check the IP/token, and that the KHAREJ side said READY.${N}"
    fi
    echo -e "${Y}You can now press Enter on the KHAREJ side to stop it.${N}"
    test_cleanup; trap - INT
}
 
test_kharej() {
    echo -e "${C}=== Transport test: KHAREJ side ===${N}"
    echo -ne "${Y}IRAN server IP: ${N}"; read iranip
    echo -ne "${Y}Test token (shown on the IRAN side): ${N}"; read token
    [ -z "$iranip" ] || [ -z "$token" ] && { echo -e "${R}IP and token required${N}"; return; }
    command -v python3 >/dev/null 2>&1 || { echo -e "${R}python3 is required (apt install -y python3)${N}"; return; }
    download_bin >/dev/null
    TDIR=/root/bh-test-kharej; test_cleanup; mkdir -p "$TDIR/www"
    trap 'test_cleanup; exit 1' INT
    head -c 1024 /dev/urandom > "$TDIR/www/s"
    head -c 100M /dev/urandom > "$TDIR/www/big"
    python3 -m http.server $((TBASE+200)) --bind 127.0.0.1 --directory "$TDIR/www" > "$TDIR/web.log" 2>&1 & TPIDS+=($!)
    for i in "${!TRANSPORTS[@]}"; do
        cat > "$TDIR/c$i.toml" << EOF
[client]
remote_addr = "${iranip}:$((TBASE+i))"
transport = "${TRANSPORTS[$i]}"
token = "${token}"
connection_pool = 8
keepalive_period = 75
dial_timeout = 10
retry_interval = 3
nodelay = true
EOF
        apply_turbo_cfg "$TDIR/c$i.toml"
        "$DIR/backhaul" -c "$TDIR/c$i.toml" > "$TDIR/c$i.log" 2>&1 & TPIDS+=($!)
    done
    sleep 2
    echo -e "${G}✅ READY${N} — now press Enter on the IRAN side."
    echo -ne "${Y}When the IRAN side shows the results, press Enter here to stop...${N}"; read
    test_cleanup; trap - INT
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
    echo "  7. Transport test: IRAN side   (run first)"
    echo "  8. Transport test: KHAREJ side"
    echo "  9. TURBO: optimize speed (this server)"
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
        7) test_iran; pause ;;
        8) test_kharej; pause ;;
        9) turbo_all; pause ;;
        0) exit 0 ;;
        *) echo -e "${R}Invalid${N}"; pause ;;
    esac
done
 
Claude finished the response
