# Tunneled Torrents

Make sure all torrents-related traffic goes through the tunnel.

## Requirements

- `transmission-daemon` and/or `qbittorrent-nox` installed.
- `awg` (AmneziaWG) or `wg` (WireGuard) installed at `/usr/bin/awg` or `/usr/bin/wg`.
- `curl` installed.
- `iptables` installed.

## Usage

0. Install `transmission-daemon` and/or `qbittorrent-nox`. Make sure you deleted the "transmission" and "qbittorrent" packages, as these may interact unpredictably with the daemons.

1. Obtain a wg or awg config allowing you to access the other machine (hint: make sure routing "there" passes your traffic).

2. Put this config into this directory.

3. **As your user**, run `sudo ./install.sh`; it will create 2 service files for you and register them in systemd. Safe to re-run any time, e.g. after a new config.

4. Start services on demand by `sudo systemctl start torrent-q` or `sudo systemctl start torrent-t`. Only one can run at a time - they're mutually exclusive, since both would reuse the same tunnel identity from the one config you dropped in.

5. Go to `qbittorrent:8080` or `transmission:9091` in your browser, have fun (to not remember addresses, these are printed in `systemctl status torrent-q`/`systemctl status torrent-t`).

## Data

- qBittorrent: `~/torrents/qBittorrent/`
- Transmission: `~/torrents/transmission/`

## Uninstall

Run `sudo ./uninstall.sh`. It stops the services and removes everything `install.sh` added (units, tunnel config, helper script, DNS files, `/etc/hosts` lines). Your data in `~/torrents` stays.

## Troubleshooting

If a service fails to start, check:

```
systemctl status torrent-q
journalctl -u torrent-q
```

(swap `torrent-q` for `torrent-t` for Transmission).

## Whys and hows

**1. Why at all**

Because you may want your torrent traffic to go through a particular host, not your own.

**2. Why not a killswitch**

Unreliable, does not guarantee ALL traffic (DNS, UPnP) goes through THE interface, has latency in killing, etc.

**3. Why not interface binding from the torrent client's config**

Unreliable, does not guarantee ALL traffic (DNS, UPnP) goes through THE interface.

**4. Why so cumbersome**

Wanted to have support for two major torrent clients and awg/wg tunnels.

**5. Why not just create a namespace and run the client from it**

Clients are not monolithic and consist of daemon + GUI, these need to interact. Long story short - it is easier to run the daemon as a service and have the Web GUI on it.

**6. Why don't use (a)wg-quick**

Due to the need to move the tunnel from the root namespace to our own, documented in wg docs.

**7. Why not a batch file instead of a service**

Easier to control lifetime.

**8. What to do if I have a new config?**

Just rerun `install.sh`.

**9. What if you have a 10.99.* net in your environment?**

Edit `install.sh` and the template files by hand, you are an engineer.

**10. Why do you think it works**

It's network namespaces, core functionality of the Linux kernel. If that doesn't work, IDK what does.
