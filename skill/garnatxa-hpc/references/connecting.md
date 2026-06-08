# Connecting to Garnatxa

## Preflight one-liner (run first)

Before debugging anything, verify SSH + key + Garnatxa tooling all work:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 garnatxa '
  whoami; id -Gn; sshare -U --noheader -P | head -1
  command -v squeue_ tapecopy >/dev/null && echo "tooling: ok" || echo "tooling: MISSING"
  ssh -o BatchMode=yes -o ConnectTimeout=3 merlot true && echo "merlot: ok" || echo "merlot: FAIL"
'
```

Failure → fix mapping:

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | Key missing on cluster | `ssh-copy-id garnatxa` (will prompt for password). |
| `Connection timed out` / `No route to host` | VPN down | Reconnect `i2sysbio.ovpn`, then retry. |
| `Host key verification failed` | Cluster reinstall or MITM | Verify fingerprint matches `SHA256:7fUYLmRdI6b1TMMz92ln3bGFCw8J9mJOv3jniz7Xt8c`. If yes: `ssh-keygen -R garnatxa.srv.cpd` and retry. If no: stop. |
| Auth ok but `Invalid account` later | Account inactive > 1 year | Open ticket. |

The asset [`assets/preflight.sh`](../assets/preflight.sh) is the agent's
canonical preflight; the asset
[`assets/ssh_config.template`](../assets/ssh_config.template) shows the
`~/.ssh/config` block (with `ControlMaster` + `ProxyJump merlot`) that
makes repeated SSH round-trips fast.

## Hostnames and endpoints

| Purpose | Value |
|---|---|
| SSH login (login node) | `garnatxa.srv.cpd` |
| Prompt after login | `[USERNAME@master ~]$` |
| Tape ops host | `merlot` (`ssh merlot` from login node) |
| GitLab | <https://garnatxadoc.uv.es/gitlab> |
| Documentation | <https://garnatxadoc.uv.es/> |
| Support tickets | <https://garnatxadoc.uv.es/support> |
| Support email | `i2sysbiohpc@uv.es` |
| Users mailing list | `i2sysbio-hpcusers@uv.es` (auto-subscribed) |
| Banner help file (on cluster) | `/doc/garnatxa_guide.txt` |
| Usage stats (on cluster) | `/doc/statistics` |
| ECDSA host key fingerprint | `SHA256:7fUYLmRdI6b1TMMz92ln3bGFCw8J9mJOv3jniz7Xt8c` |

## Requesting an account

Only the **PI (main researcher)** of an I2SysBio group can request accounts. Go to
<https://garnatxadoc.uv.es/support>, sign in with the same Garnatxa credentials,
open a ticket under topic *Garnatxa HPC / New Account Requests*, fill in PI and
new-user info. New users get credentials by email and are auto-subscribed to
`i2sysbio-hpcusers@uv.es`.

External collaborators: contact support — yearly rates apply.

## VPN

External access is blocked. From outside the UV network you must run a VPN first.

Two options:

- **I2SysBio VPN** — config file `i2sysbio.ovpn`, credentials = your Garnatxa
  username + password. Open to anyone with a Garnatxa account.
- **UV VPN** — config file `vpn_uv_es.ovpn`. Only for users with a UV account
  (`user@uv.es` or `user@alumni.uv.es`). Skip the "Step 0" config download —
  this file already replaces it.

Clients per OS:

- macOS: `openvpn-connect-3.3.6.4368_signed.dmg` (OpenVPN Connect 3.3.6) **or**
  the `openvpn` CLI via Homebrew (`brew install openvpn`).
- Windows: `OpenVPN-2.5.7-I602-amd64.msi` (OpenVPN 2.5.7).
- Linux: distro package `openvpn`.

### macOS setup (GUI — OpenVPN Connect)

1. Download `i2sysbio.ovpn`.
2. Install `openvpn-connect-3.3.6.4368_signed.dmg`.
3. Open OpenVPN Connect → **File** tab → **Browse** → select `i2sysbio.ovpn`.
4. Enter Garnatxa username + password → **Connect**.
5. Reconnect each session from the menu-bar icon (`i2sysbio` profile).

### macOS setup (CLI — Homebrew + openvpn)

Use this when you want to connect from the terminal, script it, or let an agent
bring the VPN up. The catch on macOS: `sudo openvpn ./i2sysbio.ovpn` needs an
interactive TTY for three secrets (sudo password, Garnatxa username, Garnatxa
password), so it hangs in a non-interactive shell. The bundled
[`vpn_connect_macos.sh`](../assets/vpn_connect_macos.sh) helper solves this by
collecting all three through native macOS **secure dialogs** — nothing is echoed
to the terminal, process list, or shell history.

```bash
brew install openvpn                       # one-time: installs /opt/homebrew/sbin/openvpn
mkdir -p ~/.config/garnatxa
# Download the profile straight from the live docs (no login needed):
curl -fSL -o ~/.config/garnatxa/i2sysbio.ovpn \
  https://garnatxadoc.uv.es/_downloads/ca402cace40e854fd0461fd7a311cb01/i2sysbio.ovpn

# Connect — answer the three secure popups (VPN user, VPN pass, admin password):
assets/vpn_connect_macos.sh ~/.config/garnatxa/i2sysbio.ovpn

# Disconnect + shred temp credential files:
assets/vpn_disconnect_macos.sh
```

The script verifies success by probing the cluster login host `10.1.0.6:22`
(only reachable *over* the VPN; probed by IP so it works regardless of DNS).
Confirm manually any time with:

```bash
ifconfig | grep -A2 '^utun'          # a new utunN with a 172.16.x VPN-internal IP
nc -z -w6 10.1.0.6 22 && echo "tunnel up"
```

**Split-tunnel by default — this matters.** The shipped `i2sysbio.ovpn`
contains `redirect-gateway def1`, i.e. it is **full-tunnel**: it forces *all*
your traffic through Garnatxa's egress, which is slow and heavily firewalled
(github times out, ICMP is dropped, general browsing crawls — the docs warn
"otherwise you lose general internet while connected"). `vpn_connect_macos.sh`
therefore comments out `redirect-gateway` and routes only the cluster subnet
(`10.1.0.0/16`) through the tunnel, leaving your normal internet untouched.
Cluster access (SSH, `scp`, `rsync`) still works because the cluster routes and
DNS are kept. If you genuinely need everything tunnelled, set
`VPN_FULL_TUNNEL=1 assets/vpn_connect_macos.sh …`.

> Symptom of an accidental full-tunnel: right after connecting, `ping 1.1.1.1`
> fails, `curl https://github.com` times out, and browsing is slow. Check with
> `route -n get 1.1.1.1` — if `interface:` is `utun*`, you're full-tunnelled;
> reconnect split-tunnel (the default) or disconnect.

Under the hood it runs `sudo openvpn --config <profile> --auth-user-pass <file>
--daemon`, which is exactly the plain-CLI path below with the credential prompts
handled for you. On OpenVPN 2.7 (current Homebrew) two log warnings are benign:
`DEPRECATED OPTION: --persist-key` (keys are always persisted now) and
`Unrecognized option ... block-outside-dns` (a Windows-only directive).

### Windows setup

1. Download `i2sysbio.ovpn`.
2. Install `OpenVPN-2.5.7-I602-amd64.msi`.
3. Right-click the OpenVPN tray icon → **Import file** → pick `i2sysbio.ovpn`.
4. Right-click the tray icon → `i2sysbio` → **Connect**.
5. Enter Garnatxa credentials. Tray icon turns green when connected.

### Ubuntu setup (GUI)

1. Download `i2sysbio.ovpn`.
2. Network Settings → **VPN** → **+** → **Import from file…** → select
   `i2sysbio.ovpn`.
3. Enter Garnatxa username and password → **Add**.
4. **IPv4 tab → enable "Use this connection only for resources on its network"** —
   otherwise you lose general internet while connected.
5. Connect from the network menu. Label `UV` or `I2SysBio` appears when active.

### CLI / generic UNIX

Install OpenVPN:

```bash
# Debian / Ubuntu
sudo apt install openvpn

# RHEL / Rocky / Alma (needs EPEL)
sudo dnf -y install epel-release
sudo dnf -y install openvpn
```

Connect (keep the terminal open for the lifetime of the session):

```bash
sudo openvpn ./i2sysbio.ovpn
```

Prompts: local user password (sudo), then Garnatxa username, then Garnatxa
password. Success looks like `Initialization Sequence Completed`. The benign
warning `Unrecognized option ... block-outside-dns` is harmless on OpenVPN 2.5
through 2.7 (on 2.7 you also see `DEPRECATED OPTION: --persist-key`, equally
harmless). On macOS, prefer [`vpn_connect_macos.sh`](../assets/vpn_connect_macos.sh)
so the three prompts arrive as secure dialogs instead of TTY prompts.

## SSH

Linux / macOS / Windows 10+ (built-in OpenSSH) or WSL:

```bash
ssh USERNAME@garnatxa.srv.cpd
```

First connection prompts for the host key — type `yes`. Older Windows: use
PuTTY (<http://www.putty.org/>) or similar.

Successful login shows:

```
#############################################################
##                   Welcome to I2SysBio                   ##
##                 Supercomputing facility                 ##
##       for bioinformatics & computational biology        ##
#############################################################

Basic guide about using garnatxa: /doc/garnatxa_guide.txt
Usage statistics: /doc/statistics
```

Idle SSH sessions on login nodes are closed after **8 hours of inactivity**.

## First login — change your password

```
[USERNAME@master ~]$ passwd
Changing password for user USERNAME.
Current Password: ********
New password: ********
Retype new password: ********
passwd: all authentication tokens updated successfully.
```

Policy: minimum 8 characters, at least one special character (e.g. `! % @ #`),
at least one digit.

**Important — VPN follows your password.** After changing it on Garnatxa, the
VPN must use the new password too. Disconnect the VPN, reconnect with the new
one. If your client doesn't expose a password-edit field, delete the VPN profile
and re-import `i2sysbio.ovpn` so it re-prompts.

## Passwordless SSH (key auth)

Generate (if you don't already have one):

```bash
ssh-keygen -t rsa
```

Then push your public key to the cluster:

```bash
ssh-copy-id USER@garnatxa.srv.cpd
```

After that, `ssh garnatxa` should not ask for a password. This is also a
prerequisite for the rsync-on-save VSCode workflow.

## Firewall on your local machine (mandatory)

The I2SysBio network policy requires a firewall on every device connecting in.
The recommended settings **block all incoming connections**. Inbound services
(RDP, VNC, FTP) stop working; outbound SSH/HTTPS still works. If you need an
exception, email `i2sysbiohpc@uv.es`.

### macOS

System Settings → Security & Privacy → Firewall → unlock → Turn on → Firewall
options → enable **Block all incoming connections** → OK.

### Windows

Search "firewall" → Windows Defender Firewall → Turn on for both Private and
Public → tick **Block all incoming connections, including those in the list of
allowed apps** → OK.

### Ubuntu — minimal (ufw)

```bash
sudo systemctl enable ufw
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw status
```

### Ubuntu — more complete (firewalld; drops inbound SSH)

```bash
sudo apt -y install firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld
sudo firewall-cmd --zone public --remove-service=ssh --permanent
sudo firewall-cmd --reload
```

Note: outbound SSH to Garnatxa still works. Only inbound SSH to your laptop is
dropped.

## Support

Preferred: <https://garnatxadoc.uv.es/support> → new ticket → topic
`[Garnatxa HPC]`. Email `i2sysbiohpc@uv.es` is the fallback.

## VPN/connectivity downloads (live docs: <https://garnatxadoc.uv.es/>)

- **I2SysBio VPN config** (same file for macOS, Windows, Ubuntu):
  <https://garnatxadoc.uv.es/_downloads/ca402cace40e854fd0461fd7a311cb01/i2sysbio.ovpn>
- UV VPN config:
  <https://garnatxadoc.uv.es/_downloads/a8177e5ca586ad246093bc5f05784bf0/vpn_uv_es.ovpn>
- macOS OpenVPN Connect installer:
  <https://garnatxadoc.uv.es/_downloads/a1be754d3dbf45c6a289d71b74d7bacc/openvpn-connect-3.3.6.4368_signed.dmg>
- Windows OpenVPN installer:
  <https://garnatxadoc.uv.es/_downloads/81d2e871b41b22f3b7af11badd34f0b6/OpenVPN-2.5.7-I602-amd64.msi>

These are public download links — a bare `curl -fSL -o <file> <url>` works (the
profile starts with `client` / `remote 147.156.158.10`), no login required.
