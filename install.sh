#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "run this as root"
    exit 1
fi

if [[ -z "${SUDO_USER:-}" ]]; then
    echo "ERROR: run via 'sudo $0', not as root directly - the daemons run as the invoking user" >&2
    exit 1
fi
RUN_USER="$SUDO_USER"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
if [[ -z "$RUN_HOME" ]]; then
    echo "ERROR: could not resolve home directory for $RUN_USER" >&2
    exit 1
fi
echo "Service user: $RUN_USER ($RUN_HOME)"

mapfile -t QBT_INSTANCES < <(systemctl list-unit-files --no-legend 'qbittorrent-nox@*.service' | awk '{print $1}')

for svc in transmission-daemon "${QBT_INSTANCES[@]}"; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        echo "ERROR: system service '$svc' is enabled - it will bind the daemon outside the isolated netns. Disable it first: sudo systemctl disable --now $svc" >&2
        exit 1
    fi
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "ERROR: system service '$svc' is currently running outside the isolated netns. Stop it first: sudo systemctl stop $svc" >&2
        exit 1
    fi
done

SRC="$(cd "$(dirname "$0")" && pwd)"

mapfile -t CONF_FILES < <(find "$SRC" -maxdepth 1 -name '*.conf' -print)

if [[ ${#CONF_FILES[@]} -eq 0 ]]; then
    echo "ERROR: no .conf file found in $SRC" >&2
    exit 1
elif [[ ${#CONF_FILES[@]} -gt 1 ]]; then
    echo "ERROR: multiple .conf files found:" >&2
    printf '  %s\n' "${CONF_FILES[@]}" >&2
    exit 1
fi

AWG_CONF="${CONF_FILES[0]}"
echo "AWG config: $AWG_CONF"

VPS_ADDR="$(grep -m1 -E '^[[:space:]]*Address[[:space:]]*=' "$AWG_CONF" | cut -d= -f2- | tr -d ' ' | cut -d, -f1)"
if [[ -z "$VPS_ADDR" ]]; then
    echo "ERROR: no Address= line found in $AWG_CONF" >&2
    exit 1
fi
echo "VPS tunnel address: $VPS_ADDR"

VPS_PRIVKEY="$(grep -m1 -E '^[[:space:]]*PrivateKey[[:space:]]*=' "$AWG_CONF" | cut -d= -f2- | tr -d ' ')"
if [[ -z "$VPS_PRIVKEY" ]]; then
    echo "ERROR: no PrivateKey= line found in $AWG_CONF" >&2
    exit 1
fi

is_amnezia_conf() {
    grep -qE '^[[:space:]]*Jc[[:space:]]*=' "$1"
}

if is_amnezia_conf "$AWG_CONF"; then
    TOOL=/usr/bin/awg
    LINKTYPE=amneziawg
else
    TOOL=/usr/bin/wg
    LINKTYPE=wireguard
fi
echo "Tunnel tool: $TOOL (link type: $LINKTYPE)"

VPS_PUBKEY="$(echo "$VPS_PRIVKEY" | "$TOOL" pubkey)"
echo "Peer public key: $VPS_PUBKEY"

SED_ARGS=(-e "s|@VPS_ADDR@|$VPS_ADDR|" -e "s|@VPS_PUBKEY@|$VPS_PUBKEY|" -e "s|@RUN_USER@|$RUN_USER|" -e "s|@RUN_HOME@|$RUN_HOME|" -e "s|@TOOL@|$TOOL|" -e "s|@LINKTYPE@|$LINKTYPE|")
sed "${SED_ARGS[@]}" "$SRC/torrent-q.service.in" > /etc/systemd/system/torrent-q.service
sed "${SED_ARGS[@]}" "$SRC/torrent-t.service.in" > /etc/systemd/system/torrent-t.service
chmod 644 /etc/systemd/system/torrent-q.service /etc/systemd/system/torrent-t.service

# We use awg/wg, not awg-quick/wg-quick - Address/DNS are -quick-only
# fields (per wg(8)), we wire addressing/DNS ourselves; drop them.
mkdir -p /etc/tunneled-torrents
grep -vE '^[[:space:]]*(Address|DNS)[[:space:]]*=' "$AWG_CONF" > /etc/tunneled-torrents/vps.conf
chmod 600 /etc/tunneled-torrents/vps.conf

install -D -m 755 "$SRC/mgmt-fw.sh" /usr/local/lib/tunneled-torrents/mgmt-fw.sh

for ns in torrent-qb torrent-tr; do
    mkdir -p "/etc/netns/$ns"
    echo "nameserver 9.9.9.9" > "/etc/netns/$ns/resolv.conf"
done

install -d -o "$RUN_USER" -g "$RUN_USER" -m 700 \
    "$RUN_HOME/torrents/qBittorrent/config" \
    "$RUN_HOME/torrents/qBittorrent/data" \
    "$RUN_HOME/torrents/qBittorrent/cache"

install -d -o "$RUN_USER" -g "$RUN_USER" -m 755 \
    "$RUN_HOME/torrents/transmission/downloads" \
    "$RUN_HOME/torrents/transmission/incomplete" \
    "$RUN_HOME/torrents/transmission/torrents"

chown -R "$RUN_USER:$RUN_USER" "$RUN_HOME/torrents"

sed "s|@RUN_HOME@|$RUN_HOME|g" "$SRC/qBittorrent.conf.in" > "$RUN_HOME/torrents/qBittorrent/config/qBittorrent.conf"
sed "s|@RUN_HOME@|$RUN_HOME|g" "$SRC/transmission-settings.json.in" > "$RUN_HOME/torrents/transmission/settings.json"
chown "$RUN_USER:$RUN_USER" \
    "$RUN_HOME/torrents/qBittorrent/config/qBittorrent.conf" \
    "$RUN_HOME/torrents/transmission/settings.json"

for entry in "10.99.0.2 qbittorrent" "10.99.1.2 transmission"; do
    grep -qxF "$entry" /etc/hosts || echo "$entry" >> /etc/hosts
done

systemctl daemon-reload

echo "Done. Start with:"
echo "  sudo systemctl start torrent-q"
echo "  sudo systemctl start torrent-t"
