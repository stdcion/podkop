#!/bin/sh

echo "=========================================="
echo "  Routerich firstboot configuration"
echo "=========================================="
echo ""
echo "Tip: this script will ask for your ISP DNS server IP."
echo "To find it, run this command before starting:"
echo ""
echo "  ifstatus wan | jsonfilter -e '@[\"dns-server\"][*]'"
echo ""
printf "Continue? [Y/n]: "
read -r ans
case "$ans" in
    [nN]*) echo "Exiting. Run the commands above to find your ISP DNS, then re-run this script."; exit 0 ;;
esac
echo ""

GITHUB_RAW_URL="https://raw.githubusercontent.com/stdcion/podkop/main/devices/routerich-ax3000"
TOGGLE_SCRIPT_URL="${GITHUB_RAW_URL}/toggle_podkop"
TOGGLE_SCRIPT_PATH="/usr/bin/toggle_podkop"

# Configuration defaults
DEFAULT_HOSTNAME="Routerich"
DEFAULT_ROUTER_IP="192.168.1.1"
DEFAULT_ROOT_PASS="toor"
DEFAULT_ISP_DNS=""
DEFAULT_DAILY_REBOOT="y"
DEFAULT_REBOOT_TIME="4:20"

# Initialize variables
HOSTNAME="${DEFAULT_HOSTNAME}"
ROUTER_IP="${DEFAULT_ROUTER_IP}"
ROOT_PASS="${DEFAULT_ROOT_PASS}"
ISP_DNS="${DEFAULT_ISP_DNS}"
DAILY_REBOOT="${DEFAULT_DAILY_REBOOT}"
REBOOT_TIME="${DEFAULT_REBOOT_TIME}"

# Logging
LOG_FILE="/tmp/router_config.log"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

validate_ip() {
    echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || {
        log "Invalid IP address: $1"
        exit 1
    }
}

validate_wifi_key() {
    [ ${#1} -ge 8 ] || {
        log "WiFi key must be at least 8 characters"
        exit 1
    }
}

config_hostname() {
    log "Setting hostname..."
    uci set system.@system[0].hostname="${HOSTNAME}"
    uci commit system
    service system restart
}

config_https_access() {
    log "Setting HTTPS access..."
    uci set uhttpd.main.redirect_https='1'
    uci commit uhttpd
    service uhttpd reload
}

config_root_pass() {
    log "Setting root password..."
    ubus call luci setPassword '{"username":"root", "password":"'"${ROOT_PASS}"'"}'
}

config_router_ip() {
    log "Configuring router IP..."
    uci set network.lan.ipaddr="${ROUTER_IP}"
    uci commit network
}

config_ntp() {
    log "Configuring NTP..."
    uci set system.@system[0].timezone='MSK-3'
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.ntp.enabled='1'
    uci set system.ntp.enable_server='0'
    uci delete system.ntp.server
    uci add_list system.ntp.server='216.239.35.0'
    uci add_list system.ntp.server='216.239.35.4'
    uci add_list system.ntp.server='216.239.35.8'
    uci add_list system.ntp.server='216.239.35.12'
    uci add_list system.ntp.server='162.159.200.123'
    uci add_list system.ntp.server='162.159.200.1'
    uci commit
    service sysntpd restart
    service system restart
}

config_wifi() {
    log "Configuring WiFi..."

    # 2.4GHz
    uci set wireless.radio0.channel='6'
    uci set wireless.radio0.htmode='HE40'
    uci set wireless.radio0.country='PA'
    uci set wireless.radio0.txpower='26'
    uci set wireless.radio0.cell_density='0'
    uci set wireless.radio0.disabled='0'
    uci set wireless.default_radio0.network='lan'
    uci set wireless.default_radio0.encryption='psk2'
    uci set wireless.radio0.noscan='0'

    # 5GHz
    uci set wireless.radio1.channel='36'
    uci set wireless.radio1.htmode='HE80'
    uci set wireless.radio1.country='PA'
    uci set wireless.radio1.txpower='27'
    uci set wireless.radio1.cell_density='0'
    uci set wireless.radio1.disabled='0'
    uci set wireless.default_radio1.network='lan'
    uci set wireless.default_radio1.encryption='psk2'

    uci commit wireless
}

config_button() {
    log "Configuring button for podkop toggle..."

    mkdir -p /etc/hotplug.d/button
    cat << "EOF" > /etc/hotplug.d/button/00-button
    source /lib/functions.sh

    do_button () {
        local button
        local action
        local handler
        local min
        local max

        config_get button "${1}" button
        config_get action "${1}" action
        config_get handler "${1}" handler
        config_get min "${1}" min
        config_get max "${1}" max

        [ "${ACTION}" = "${action}" -a "${BUTTON}" = "${button}" -a -n "${handler}" ] && {
            [ -z "${min}" -o -z "${max}" ] && eval ${handler}
            [ -n "${min}" -a -n "${max}" ] && {
                [ "${min}" -le "${SEEN}" -a "${max}" -ge "${SEEN}" ] && eval ${handler}
            }
        }
    }

    config_load system
    config_foreach do_button button
EOF

    uci add system button
    uci set system.@button[-1].name='podkop_toggle'
    uci set system.@button[-1].button='BTN_0'
    uci set system.@button[-1].action='released'
    uci set system.@button[-1].min='1'
    uci set system.@button[-1].max='5'
    uci set system.@button[-1].handler="$TOGGLE_SCRIPT_PATH toggle"
    uci set system.@button[-1].enabled='1'
    uci commit system
}

config_dnsmasq() {
    log "Configuring dnsmasq-ru..."

    cat > /etc/dnsmasq-ru.conf << EOF
port=5454
listen-address=127.0.0.10
bind-interfaces
no-resolv
no-hosts
no-dhcp-interface=*
all-servers
server=77.88.8.8
server=77.88.8.1
$([ -n "$ISP_DNS" ] && echo "server=$ISP_DNS")
cache-size=1000
no-negcache
domain-needed
bogus-priv
EOF

    cat > /etc/init.d/dnsmasq-ru << 'INITEOF'
#!/bin/sh /etc/rc.common

START=96
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/dnsmasq -C /etc/dnsmasq-ru.conf -k
    procd_set_param respawn
    procd_set_param pidfile /var/run/dnsmasq-ru.pid
    procd_close_instance
}
INITEOF

    chmod +x /etc/init.d/dnsmasq-ru
    /etc/init.d/dnsmasq-ru enable
    /etc/init.d/dnsmasq-ru start

    # Disable conflicting DNS services
    for svc in stubby stubby-intercept https-dns-proxy; do
        if [ -x "/etc/init.d/$svc" ]; then
            log "Stopping and disabling $svc..."
            "/etc/init.d/$svc" stop 2>/dev/null
            "/etc/init.d/$svc" disable 2>/dev/null
        fi
    done

    # Configure dns-failsafe-proxy: primary = podkop, failback = dnsmasq-ru
    if [ -f /etc/config/dns-failsafe-proxy ]; then
        log "Configuring dns-failsafe-proxy..."
        uci set dns-failsafe-proxy.main.dns_ip='127.0.0.42'
        uci set dns-failsafe-proxy.main.dns_port='53'
        uci set dns-failsafe-proxy.main.failback_ip='127.0.0.10'
        uci set dns-failsafe-proxy.main.failback_port='5454'
        uci set dns-failsafe-proxy.main.connect_timeout='1000'
        uci set dns-failsafe-proxy.main.session_timeout='5000'
        uci commit dns-failsafe-proxy
        if [ -x /etc/init.d/dns-failsafe-proxy ]; then
            /etc/init.d/dns-failsafe-proxy restart 2>/dev/null
        fi
        log "dns-failsafe-proxy configured: dns=127.0.0.42:53, failback=127.0.0.10:5454"
    fi

    log "dnsmasq-ru configured on 127.0.0.10:5454"
}

disable_ipv6() {
    log "Disabling IPv6..."

    uci set network.lan.ipv6='0'
    uci set network.wan.ipv6='0'
    uci set network.lan.delegate='0'
    uci -q delete dhcp.lan.dhcpv6
    uci -q delete dhcp.lan.ra
    uci -q delete network.globals.ula_prefix
    uci commit

    /etc/init.d/odhcpd stop
    /etc/init.d/odhcpd disable

    /etc/init.d/network restart

    log "IPv6 disabled"
}

config_daily_reboot() {
    if [ "$DAILY_REBOOT" != "y" ]; then
        log "Daily reboot skipped"
        return
    fi

    local hour minute
    hour=$(echo "$REBOOT_TIME" | cut -d: -f1)
    minute=$(echo "$REBOOT_TIME" | cut -d: -f2)

    log "Setting daily reboot at ${REBOOT_TIME}..."

    local cron_file="/etc/crontabs/root"
    local cron_entry="${minute} ${hour} * * * /sbin/reboot"

    # Ensure cron directory and file exist
    mkdir -p "$(dirname "$cron_file")"
    touch "$cron_file"

    # Remove existing reboot cron entries if any
    grep -v '/sbin/reboot' "$cron_file" > "${cron_file}.tmp" && mv "${cron_file}.tmp" "$cron_file"

    # Add new reboot cron entry
    echo "$cron_entry" >> "$cron_file"

    # Ensure cron is enabled and running
    /etc/init.d/cron enable
    /etc/init.d/cron restart

    log "Daily reboot configured at ${REBOOT_TIME}"
}

install_toggle_script() {
    log "Downloading toggle_podkop..."
    wget -O "$TOGGLE_SCRIPT_PATH" "$TOGGLE_SCRIPT_URL" || {
        log "Failed to download toggle_podkop"
        exit 1
    }
    chmod +x "$TOGGLE_SCRIPT_PATH"

    # Sync LED state with podkop on boot
    if ! grep -q 'toggle_podkop init' /etc/rc.local 2>/dev/null; then
        sed -i '/^exit 0$/d' /etc/rc.local 2>/dev/null
        echo "$TOGGLE_SCRIPT_PATH init" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
    fi
}

get_user_input() {
    printf "Enter Hostname [%s]: " "${HOSTNAME}"
    read -r input
    [ -n "$input" ] && HOSTNAME="$input"

    printf "Enter Router IP [%s]: " "${ROUTER_IP}"
    read -r input
    [ -n "$input" ] && ROUTER_IP="$input"
    validate_ip "$ROUTER_IP"

    printf "Enter root password [%s]: " "${ROOT_PASS}"
    read -r input
    [ -n "$input" ] && ROOT_PASS="$input"

    printf "Enable daily reboot? [Y/n]: "
    read -r input
    case "$input" in
        [nN]*) DAILY_REBOOT="n" ;;
    esac

    if [ "$DAILY_REBOOT" = "y" ]; then
        printf "Daily reboot time (HH:MM, 24h) [%s]: " "${REBOOT_TIME}"
        read -r input
        [ -n "$input" ] && REBOOT_TIME="$input"
    fi

    printf "Enter ISP DNS server IP (e.g. 192.168.100.1) or leave empty to skip: "
    read -r input
    if [ -n "$input" ]; then
        validate_ip "$input"
        ISP_DNS="$input"
    fi
}

main() {
    log "Starting router configuration..."
    get_user_input

    config_ntp
    log "Waiting for NTP sync..."
    sleep 5
    opkg update && opkg install kmod-nft-tproxy kmod-button-hotplug
    install_toggle_script
    config_hostname
    config_root_pass
    config_wifi
    config_router_ip
    config_https_access
    config_button
    config_dnsmasq
    disable_ipv6
    config_daily_reboot

    log "Configuration completed!"
    echo "Changes logged to $LOG_FILE"

    printf "Reboot now? [y/N]: "
    read -r choice
    case "$choice" in
        [yY]*) reboot ;;
        *) echo "Reboot manually to apply changes" ;;
    esac
    reload_config
}

main
