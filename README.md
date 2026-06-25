# Linux-VALVE-server-picker

This is a dependency-light tool to block specific Valve Datagram relay (SDR) region, so you don't get matdched in them. This works for **CS2**, **Deadlock**, **Marathon** (supposedly) and **THE FINALS**

Pure Bash + `curl` + `jq`. No build step, no GUI framework, no installer, easy to use!!1

## Why this exists

Most of the others server picker and/ooor server blockers for valve games Windows builds block relays correctly using outbound firewall rules. Their **Linux builds**, however, add the rule in the wrong direction:

```csharp
// Linux build — blocks the relay's replies to you, not your connection to it
process.StartInfo.Arguments = "iptables -A INPUT -s " + ipAddresses + " -j DROP";
```

```csharp
// Windows build — correctly blocks outbound traffic to the relay
firewallRule.Direction = NET_FW_RULE_DIRECTION_.NET_FW_RULE_DIR_OUT;
firewallRule.RemoteAddresses = ipAddresses;
```

On linux, your client's connection attempt still reaches the relay, and only the relay's replies get silently dropped on your end. The block doesn't actually keep matchmaking from routing you there. This script fixes that by using `OUTPUT`/`-d` (destination) instead of `INPUT`/`-s` (source), matching what the Windows build already does correctly.

It pulls relay data from the same source server-picker-x uses: Valve's public `GetSDRConfig` Steam Web API. No API key, no scraping, no hardcoded IP list to go stale.

## Requirements

- Linux with `iptables` (works fine alongside `ufw`, rules are added to the same `OUTPUT` chain `ufw` manages)
- `bash`, `curl`, `jq`
- `sudo` privileges (firewall rules require it)

Install `jq` if you don't have it:
```bash
sudo apt install jq        # Debian/Ubuntu
sudo pacman -S jq          # Arch/CachyOS
sudo dnf install jq        # Fedora
```

## Installation

```bash
git clone https://github.com/nelzv/linux-valve-server-picker
cd linux-valve-server-picker
chmod +x linux-valve-server-picker.sh
```

## Usage

```bash
# Lists every available relay region for a game, with live IPs
./linux-valve-server-picker.sh list cs2

# Blocks one or more regions by POP code (from the list output)
./linux-valve-server-picker.sh block cs2 jnb dxb

# Sees everything this script currently has blocked
./linux-valve-server-picker.sh status

# Unblocks a specific region
./linux-valve-server-picker.sh unblock cs2 jnb

# Removes every rule this script has added. This leaves the rest of your firewall alone c:
./linux-valve-server-picker.sh reset
```

Supported games and their Steam AppIDs:

| Game | Key |
|---|---|
| Counter-Strike 2 | `cs2` |
| Deadlock | `deadlock` |
| Marathon | `marathon` |
| THE FINALS | `finals` |

## How it works

1. Fetches `https://api.steampowered.com/ISteamApps/GetSDRConfig/v1/?appid=<id>` for the chosen game; Valve's official list of relay points-of-presence (POPs) and their IPv4 relay addresses.
2. For each POP you choose to block, adds one `iptables -A OUTPUT -d <relay-ip> -j DROP` rule per relay IP, tagged with a comment (`csp_<game>_<pop>`) so the script always knows which rules are its own.
3. Tracks what it's blocked in `~/.config/linux-valve-server-picker/blocked.tsv`, so `status`, `unblock`, and `reset` work precisely without ever touching unrelated firewall rules.

## Notes

||- This only adds firewall rules it NEVER, EVER touches game files, so there's no realistic ban risk from using it.
||- A game's in-game datacenter/ping settings menu (e.g. CS2's "Max Acceptable Ping" list) will still *show* a blocked region. that list reflects every datacenter that exists, not what your machine can currently reach. The block is working if your actual matchmaking ping stops reflecting that region, not if it disappears from the settings menu.
||- Rules don't persist across reboot by default (same as most manual `iptables` rules), re-run `block` for your preferred regions each session, or look into `iptables-save`/`netfilter-persistent` if you want it tobe *permanent*.
||- Re-routing can happen mid-session due to how Steam Datagram Relay works. Blocking the obvious nearby-but-bad-routing regions is usually enough, blocking everything except your one preferred region is usually unnecessary and can cause matchmaking timeouts if you block too aggressively. So take notes.

## License

MIT . see [LICENSE](LICENSE). This is an independent rewrite using Valve's public API; no code is shared with other server pickers, so there's no licensing entanglement between the two.

## Credit

Inspired by and reports the same upstream bug found in [FN-FAL113/server-picker-x](https://github.com/FN-FAL113/server-picker-x), a great tool, worth using too, especially if you want the GUI/ping-display experience this script doesn't try to replicate; Take a look.
