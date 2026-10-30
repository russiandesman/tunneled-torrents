#!/bin/sh
# Usage: mgmt-fw.sh up|down <iface> <webui-port>
#
# Hardens a host-side mgmt veth, which is a /30 point-to-point link meant only
# for host <-> netns WebUI access:
# - sysctl: never forward packets arriving on this interface to anywhere else,
#   no matter what ip_forward or the routing table say.
# - FORWARD DROP: belt-and-suspenders, same effect, explicit either way.
# - INPUT/OUTPUT: the daemon's WebUI binds 0.0.0.0, so without this the whole
#   netns (BT/DHT ports too) would be reachable over this link; restrict the
#   host's side of it to just the WebUI port. The INPUT ACCEPT also requires an
#   ESTABLISHED connection, so the netns cannot open connections to the host
#   by merely using the WebUI port as source port.
# - IPv6 off on the host end: the rules above are IPv4-only, and link-local
#   IPv6 would otherwise let the netns reach host services listening on ::.
# Rules are inserted broad-then-narrow so the narrow ACCEPT ends up checked first.
# iptables rules outlive the interface, so "down" must remove them.

action=$1
iface=$2
port=$3
ipt=/usr/sbin/iptables

rules() {
    op=$1
    $ipt "$op" OUTPUT -o "$iface" -j DROP
    $ipt "$op" OUTPUT -o "$iface" -p tcp --dport "$port" -j ACCEPT
    $ipt "$op" INPUT -i "$iface" -j DROP
    $ipt "$op" INPUT -i "$iface" -p tcp --sport "$port" -m conntrack --ctstate ESTABLISHED -j ACCEPT
    $ipt "$op" FORWARD -i "$iface" -j DROP
    $ipt "$op" FORWARD -o "$iface" -j DROP
}

case "$action" in
    up)
        set -e
        /usr/sbin/sysctl -qw "net.ipv4.conf.$iface.forwarding=0"
        /usr/sbin/sysctl -qw "net.ipv6.conf.$iface.disable_ipv6=1"
        rules -I
        ;;
    down)
        rules -D || true
        ;;
    *)
        echo "usage: $0 up|down <iface> <port>" >&2
        exit 2
        ;;
esac
