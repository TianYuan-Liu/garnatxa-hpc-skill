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

- macOS: `openvpn-connect-3.3.6.4368_signed.dmg` (OpenVPN Connect 3.3.6).
- Windows: `OpenVPN-2.5.7-I602-amd64.msi` (OpenVPN 2.5.7).
- Linux: distro package `openvpn`.

### macOS setup

1. Download `i2sysbio.ovpn`.
2. Install `openvpn-connect-3.3.6.4368_signed.dmg`.
3. Open OpenVPN Connect → **File** tab → **Browse** → select `i2sysbio.ovpn`.
4. Enter Garnatxa username + password → **Connect**.
5. Reconnect each session from the menu-bar icon (`i2sysbio` profile).

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
warning `Unrecognized option ... block-outside-dns` is harmless on OpenVPN 2.5.

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

## VPN/connectivity downloads (paths in the live docs)

- I2SysBio VPN config: `_downloads/ca402cace40e854fd0461fd7a311cb01/i2sysbio.ovpn`
- UV VPN config: `_downloads/a8177e5ca586ad246093bc5f05784bf0/vpn_uv_es.ovpn`
- macOS OpenVPN Connect installer:
  `_downloads/a1be754d3dbf45c6a289d71b74d7bacc/openvpn-connect-3.3.6.4368_signed.dmg`
- Windows OpenVPN installer:
  `_downloads/81d2e871b41b22f3b7af11badd34f0b6/OpenVPN-2.5.7-I602-amd64.msi`
