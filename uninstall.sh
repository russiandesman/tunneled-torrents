#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "run this as root"
    exit 1
fi

systemctl stop torrent-q torrent-t 2>/dev/null || true

# Stopping an inactive service skips ExecStopPost, so clean up explicitly in
# case a hard failure left rules, veths or netns behind.
/usr/local/lib/tunneled-torrents/mgmt-fw.sh down host-mgmt-qb 8080 2>/dev/null || true
/usr/local/lib/tunneled-torrents/mgmt-fw.sh down host-mgmt-tr 9091 2>/dev/null || true
ip link del host-mgmt-qb 2>/dev/null || true
ip link del host-mgmt-tr 2>/dev/null || true
ip netns del torrent-qb 2>/dev/null || true
ip netns del torrent-tr 2>/dev/null || true

rm -f /etc/systemd/system/torrent-q.service /etc/systemd/system/torrent-t.service
rm -rf /etc/tunneled-torrents /usr/local/lib/tunneled-torrents
rm -rf /etc/netns/torrent-qb /etc/netns/torrent-tr
sed -i -e '/^10\.99\.0\.2 qbittorrent$/d' -e '/^10\.99\.1\.2 transmission$/d' /etc/hosts

systemctl daemon-reload

echo "Done. Your data in ~/torrents was left in place."
