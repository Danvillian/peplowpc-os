# Security and privacy baseline

Every default PeplowPC OS changes from stock Fedora Silverblue 45, why, and how we prove it works.
Status column: **untested** until checked on a built image (Phase 0 in `ROADMAP.md`), then **verified** with a date.
First full run of `tools/check-baseline.sh` on a fresh install (Hyper-V Gen 2, Secure Boot, encrypted disk): 71 passed, 0 failed, 2026-11-06.

The rule for this list: a protection only ships on by default if an everyday user will never notice it.
Anything that could break printing, video calls, banking sites or hotel Wi-Fi is a decision, not a default
(see `DECISIONS.md`).

## Kept from Fedora (not changed, listed so nobody turns them off)

| Protection | Plain English |
|---|---|
| SELinux enforcing | Programs can only touch what their role allows, even if hacked. |
| Secure Boot with Fedora's signed kernel | The computer refuses to start a tampered-with system. We do not build our own kernel, so this keeps working. |
| Read-only `/usr` | The system files cannot be changed while the computer is running. |
| Flatpak sandboxing | Apps cannot see your files unless you give them a file. |
| Automatic rollback entry in boot menu | A bad update is one restart away from being undone. |

## Updates and trust

| Setting | Value | Why | File | Status |
|---|---|---|---|---|
| Signed system updates | Only images signed with the PeplowPC key; everything else rejected by default. Re-checked after every boot and every update | Nobody can push a fake update, even by hijacking the download | `build.sh` (policy.json), `/usr/bin/peplowpc-update` | verified 2026-11-06 |
| Automatic updates | Downloaded daily in the background, applied at next restart, never forced | Protection without surprise reboots | `bootc-fetch-apply-updates.service.d/60-peplowpc.conf` | verified 2026-11-06 |
| App updates | Every 6 hours | Browser-like apps need fast fixes | `peplowpc-flatpak-update.timer` | untested |
| App source | Flathub, verified publishers only; Fedora remote removed | Stops look-alike apps uploaded by impostors | `peplowpc-flatpak-setup` | verified 2026-11-06 |
| Daily image rebuild | 09:17 UTC | Picks up Fedora security fixes without waiting on us | `.github/workflows/build.yml` | verified 2026-11-06 |

## Kernel

| Setting | Value | Why | Status |
|---|---|---|---|
| `kernel.kptr_restrict` | 2 | Hides kernel memory addresses that exploits need | verified 2026-11-06 |
| `kernel.dmesg_restrict` | 1 | Kernel log readable by admins only | verified 2026-11-06 |
| `kernel.kexec_load_disabled` | 1 | Cannot swap in another kernel while running | verified 2026-11-06 |
| `kernel.unprivileged_bpf_disabled`, `net.core.bpf_jit_harden` | 1, 2 | Closes a common route for kernel exploits | verified 2026-11-06 |
| `kernel.perf_event_paranoid` | 2 | Limits performance counters often used in side-channel attacks | verified 2026-11-06 |
| `kernel.yama.ptrace_scope` | 1 (Fedora: 0) | One program cannot read another's memory (for example malware reading the browser) | verified 2026-11-06 |
| `kernel.sysrq`, `dev.tty.ldisc_autoload` | 0, 0 | Removes rarely used, attackable features | verified 2026-11-06 |
| `fs.protected_*`, `fs.suid_dumpable` | 2/2/1/1, 0 | Safer shared folders, no memory dumps of admin programs | verified 2026-11-06 |
| Boot args `init_on_alloc=1 init_on_free=1` | on | Memory is wiped on use and release, so secrets do not linger. Costs about 1 to 5% speed (D8) | verified 2026-11-06 |
| Boot args `slab_nomerge page_alloc.shuffle=1 randomize_kstack_offset=on` | on | Makes memory layout unpredictable for attackers | verified 2026-11-06 |
| Boot args `vsyscall=none debugfs=off` | on | Removes legacy and debug interfaces | verified 2026-11-06 |
| Blocked kernel modules | rare network protocols, FireWire, cramfs/freevxfs/jffs2, vivid | No home user needs them; all have had serious bugs | verified 2026-11-06 |
| Crash dumps | not stored | Dumps can contain passwords and open documents | verified 2026-11-06 |

Files: `usr/lib/sysctl.d/60-peplowpc-hardening.conf`, `usr/lib/bootc/kargs.d/60-peplowpc-hardening.toml`,
`usr/lib/modprobe.d/60-peplowpc-blacklist.conf`, `usr/lib/systemd/coredump.conf.d/60-peplowpc.conf`.

## Network

| Setting | Value | Why | Status |
|---|---|---|---|
| Firewall default zone | `peplowpc`: nothing incoming except printer discovery (mDNS) and IPv6 setup. Fedora Workstation leaves ports 1025 to 65535 open | Other devices on the network cannot connect in | verified 2026-11-06 |
| DNS | Quad9 over DNS-over-TLS, opportunistic (D4) | Your internet provider cannot see or sell the sites you visit; known scam and malware domains are blocked | verified 2026-11-06 |
| LLMNR | off | Old name lookup that attackers on public Wi-Fi can answer | verified 2026-11-06 |
| Wi-Fi MAC address | Random while scanning; a different stable made-up address per network | Shops, airports and hotels cannot track the laptop between places | verified 2026-11-06 |
| Hostname in DHCP | not sent | The network does not learn "Janes-Laptop" | verified 2026-11-06 |
| IPv6 privacy addresses | on | Websites do not get an address tied to your hardware | verified 2026-11-06 |
| ICMP redirects, source routing | ignored | Blocks traffic-redirect tricks on shared Wi-Fi | verified 2026-11-06 |
| Time | NTS (authenticated) from Cloudflare, Netnod, PTB, time.nl; requires 2 agreeing sources | A faked clock can make revoked certificates look valid | verified 2026-11-06 |

Files: `usr/lib/firewalld/zones/peplowpc.xml`, `usr/lib/systemd/resolved.conf.d/60-peplowpc-dns.conf`,
`usr/lib/NetworkManager/conf.d/60-peplowpc-privacy.conf`, `etc/chrony.conf`.

**Verify carefully:** test a real hotel-style Wi-Fi login page; with `Domains=~.` it may not appear (DECISIONS D4). Also, with `Domains=~.` the global Quad9 servers should win over the DNS servers handed out
by the router. Confirm with `resolvectl status` and the network audit that router DNS is not used. If it is,
add NetworkManager global DNS settings. Also confirm NetworkManager accepts `ipv4.dhcp-send-hostname` as a
global default (needs NetworkManager 1.52 or newer; check `NetworkManager --print-config` and a DHCP packet capture).

## Telemetry and data collection

| Item | Fedora default | PeplowPC OS | Status |
|---|---|---|---|
| rpm-ostree "countme" (anonymous install counting) | weekly | masked | verified 2026-11-06 |
| dnf countme in repo files | on | 0 | untested |
| ABRT crash reporting | installed on some editions | removed if present | untested |
| GNOME problem reporting, usage stats | off | off (pinned) | verified 2026-11-06 |
| Location services | on | off; apps must ask after the user turns it on | verified 2026-11-06 |
| Firefox telemetry, studies, Pocket, sponsored content | on | off by policy | untested |

## Desktop

| Setting | Value | Why |
|---|---|---|
| Screen lock | Immediately when the screen blanks; blank after 5 minutes idle | Walk-away protection |
| Notifications on lock screen | hidden | Message previews are not readable over your shoulder |
| Autorun of USB media | never | A plugged-in stick cannot start a program |
| Old trash and temp files | removed after 30 days | Less forgotten data lying around |
| Window buttons | minimize, maximize, close | Familiar to people coming from Windows |

File: `usr/share/glib-2.0/schemas/zz0-peplowpc.gschema.override`.

## Browser (Firefox, until PeplowPC Browser for Linux, D3)

Enforced through `distribution/policies.json` in the Firefox install folder under `/usr` (read-only system location):
telemetry, studies and Pocket off; HTTPS-Only; DNS-over-HTTPS to Quad9; strict tracking protection
including fingerprinting and email trackers; total cookie protection; DuckDuckGo search; no sponsored
tiles or suggestions; uBlock Origin installed and kept; Global Privacy Control on.

Mirrors `peplowpc-browser/docs/PRIVACY-BASELINE.md` where Firefox has an equivalent.
Verify on the built image at `about:policies`; check `SearchEngines` applies on the release channel.

## Expected outbound connections

The idle audit (`tools/audit-network.sh 300`) should show only these. Anything else is a bug to explain or remove.

| Host | Why | Can it be removed? |
|---|---|---|
| `dns.quad9.net` (9.9.9.9 and friends) | Encrypted DNS | No |
| `time.cloudflare.com`, `nts.netnod.se`, `ptbtime1.ptb.de`, `ntppool1.time.nl` | Authenticated time | No |
| `ghcr.io`, `pkg-containers.githubusercontent.com` | System update check | No |
| `dl.flathub.org` | App updates | No |
| `fedoraproject.org` (connectivity check) | Detects Wi-Fi login pages | Decision D5 |
| `fwupd.org` / LVFS | Firmware security updates | Keep (firmware fixes matter) |
| `odrs.gnome.org` | App reviews in GNOME Software | Decision D10 |
