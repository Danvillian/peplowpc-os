#!/usr/bin/bash
# PeplowPC OS baseline check. Run on an installed system as your normal user (not with sudo);
# it asks for your password once for the checks that need admin rights.
#   bash check-baseline.sh
# Prints PASS / FAIL / INFO per item in docs/SECURITY-BASELINE.md, then a summary.
set -uo pipefail

pass=0
fail=0
ok() { printf '  \e[32mPASS\e[0m  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \e[31mFAIL\e[0m  %s\n' "$1"; fail=$((fail + 1)); }
info() { printf '  \e[36mINFO\e[0m  %s\n' "$1"; }
check() { # description, command...
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
section() { printf '\n\e[1m%s\e[0m\n' "$1"; }

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, without sudo." >&2; exit 1; }
sudo -v || exit 1

section "Identity"
# shellcheck disable=SC1091
. /etc/os-release
check "os-release says PeplowPC OS" test "${NAME:-}" = "PeplowPC OS"
info "Image version: $(jq -r .version /usr/share/peplowpc/image-info.json 2>/dev/null)"
check "Fedora wallpaper logo add-on removed" bash -c '! rpm -q gnome-shell-extension-background-logo'

section "Boot and disk"
if command -v mokutil >/dev/null; then
    check "Secure Boot enabled" bash -c "mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'"
else
    info "mokutil not present; check Secure Boot in the VM settings"
fi
check "SELinux enforcing" bash -c "[[ \$(getenforce 2>/dev/null) == Enforcing ]]"
check "No files missing SELinux labels in /etc" bash -c "[[ -z \$(sudo find /etc -context '*unlabeled_t*' -print -quit 2>/dev/null) ]]"
check "SELinux not disabled on the boot line" bash -c "! grep -qwE 'selinux=0|enforcing=0' /proc/cmdline"
check "Disk encryption (LUKS) in use" bash -c "lsblk -o TYPE | grep -q crypt"
info "systemd-remount-fs: $(systemctl is-failed systemd-remount-fs.service 2>/dev/null) (known upstream issue on Anaconda installs; harmless so far)"
check "Boot splash theme is peplowpc" bash -c "grep -qs 'Theme=peplowpc' /etc/plymouth/plymouthd.conf"
for arg in init_on_alloc=1 init_on_free=1 slab_nomerge page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off rhgb quiet; do
    check "Kernel arg $arg" grep -qw -- "$arg" /proc/cmdline
done

section "Updates and trust"
status_json="$(sudo bootc status --format=json 2>/dev/null)"
info "Booted image: $(jq -r '.status.booted.image.image.image // "unknown"' <<<"$status_json")"
origin="$(rpm-ostree status --json 2>/dev/null | jq -r '.deployments[] | select(.booted) | ."container-image-reference" // empty')"
info "Booted origin: ${origin:-unknown}"
staged="$(rpm-ostree status --json 2>/dev/null | jq -r '.deployments[] | select(.staged) | ."container-image-reference" // empty')"
[[ -n "$staged" ]] && info "Staged for next restart: $staged"
if [[ "$origin" == ostree-image-signed:* ]]; then
    ok "Running image requires PeplowPC signature"
elif [[ "$staged" == ostree-image-signed:* ]]; then
    info "Signed updates are staged: restart to finish (not a failure)"
else
    bad "Signed updates not enabled (run: sudo peplowpc-update --ensure-signed)"
fi
check "Container policy rejects unsigned by default" bash -c "jq -e '.default[0].type == \"reject\"' /etc/containers/policy.json"
check "PeplowPC public key installed" test -s /etc/pki/containers/peplowpc.pub
check "Update timer enabled" systemctl is-enabled bootc-fetch-apply-updates.timer
check "Updates go through peplowpc-update (signed, never forces a reboot)" bash -c "systemctl show -p ExecStart bootc-fetch-apply-updates.service | grep -q peplowpc-update && ! systemctl show -p ExecStart bootc-fetch-apply-updates.service | grep -q -- '--apply'"
check "Signed-update check timer enabled" systemctl is-enabled peplowpc-signed-switch.timer
check "rpm-ostree countme masked" bash -c "[[ \$(systemctl is-enabled rpm-ostree-countme.timer 2>&1) == masked ]]"

section "Apps"
remotes="$(flatpak remotes --system --columns=name 2>/dev/null | tr '\n' ' ')"
info "Flatpak remotes: ${remotes:-none}"
check "Only Flathub verified remote" test "$(echo "$remotes" | xargs)" = "flathub-verified"
missing=()
while IFS= read -r line; do
    app="${line%%#*}"
    app="${app//[[:space:]]/}"
    [[ -z "$app" ]] && continue
    flatpak --system info "$app" >/dev/null 2>&1 || missing+=("$app")
done </usr/share/peplowpc/flatpaks.list
if ((${#missing[@]})); then bad "Starter apps missing: ${missing[*]}"; else ok "All starter apps installed"; fi
info "Starter app setup last run: $(systemctl show -p ExecMainStatus --value peplowpc-flatpak-setup.service) (0 = success)"
check "Firefox PeplowPC policies installed" bash -c "rpm -ql firefox | grep -q 'distribution/policies.json' || ls /usr/lib*/firefox/distribution/policies.json"

section "Network"
check "Firewall default zone is peplowpc" bash -c "[[ \$(sudo firewall-cmd --get-default-zone) == peplowpc ]]"
services="$(sudo firewall-cmd --zone=peplowpc --list-services 2>/dev/null)"
info "Open services: $services"
check "Firewall allows only mDNS and DHCPv6 in" test "$(tr ' ' '\n' <<<"$services" | sort | xargs)" = "dhcpv6-client mdns"
check "DNS-over-TLS configured" bash -c "resolvectl status | grep -qi 'DNSOverTLS'"
info "$(resolvectl status 2>/dev/null | grep -m1 -i 'Current DNS Server' | xargs)"
check "Global DNS is Quad9" bash -c "resolvectl dns | grep -i global | grep -q '9.9.9.9\|149.112.112.112\|2620:fe::'"
check "LLMNR off" bash -c "resolvectl status | grep -q -- '-LLMNR'"
nm_cfg="$(NetworkManager --print-config 2>/dev/null)"
check "Wi-Fi scan MAC randomization" grep -q 'wifi.scan-rand-mac-address=yes' <<<"$nm_cfg"
check "Per-network Wi-Fi MAC" grep -q 'wifi.cloned-mac-address=stable' <<<"$nm_cfg"
check "Hostname not sent over DHCP (NM accepted key)" grep -q 'ipv4.dhcp-send-hostname=0' <<<"$nm_cfg"
check "IPv6 privacy addresses" grep -q 'ipv6.ip6-privacy=2' <<<"$nm_cfg"
check "Time from NTS sources" bash -c "sudo chronyc -N authdata | grep -q NTS"
info "Time sources: $(sudo chronyc -N authdata 2>/dev/null | awk 'NR>2 {printf "%s(%s) ", $1, $2}')"

section "Kernel hardening"
while IFS='=' read -r key want; do
    [[ "$key" =~ ^[[:space:]]*(#|$) ]] && continue
    key="${key//[[:space:]]/}"
    want="${want//[[:space:]]/}"
    have="$(sudo sysctl -n "$key" 2>/dev/null)"
    if [[ "$have" == "$want" ]]; then ok "sysctl $key = $want"; else bad "sysctl $key = ${have:-missing} (want $want)"; fi
done </usr/lib/sysctl.d/60-peplowpc-hardening.conf
check "Rare protocol modules blocked (dccp)" bash -c "modprobe -n -v dccp 2>&1 | grep -q '/bin/false'"
check "Crash dumps not stored" bash -c "systemd-analyze cat-config systemd/coredump.conf | grep -q '^Storage=none'"

section "Desktop"
gs() { gsettings get "$1" "$2" 2>/dev/null; }
check "Dark mode" bash -c "[[ \"$(gs org.gnome.desktop.interface color-scheme)\" == \"'prefer-dark'\" ]]"
check "Location services off" bash -c "[[ \"$(gs org.gnome.system.location enabled)\" == false ]]"
check "USB autorun never" bash -c "[[ \"$(gs org.gnome.desktop.media-handling autorun-never)\" == true ]]"
check "Lock screen hides notifications" bash -c "[[ \"$(gs org.gnome.desktop.notifications show-in-lock-screen)\" == false ]]"
check "Problem reporting off" bash -c "[[ \"$(gs org.gnome.desktop.privacy report-technical-problems)\" == false ]]"
check "P app menu (ArcMenu) enabled" bash -c "gnome-extensions list --enabled 2>/dev/null | grep -qx arcmenu@arcmenu.com"
check "Desktop shown after login (no overview)" bash -c "[[ \$(gsettings get org.gnome.shell.extensions.arcmenu hide-overview-on-startup 2>/dev/null) == true ]]"
check "PeplowPC account picture available" test -f /usr/share/pixmaps/faces/peplowpc.png
check "Lime accent CSS for apps" test -s "$HOME/.config/gtk-4.0/gtk.css"

printf '\n\e[1mSummary:\e[0m %d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
