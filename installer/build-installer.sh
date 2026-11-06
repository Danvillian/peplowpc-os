#!/usr/bin/bash
# Runs once inside installer/Containerfile. Turns a plain Fedora bootc image into a branded
# Anaconda installer environment (the steps lorax normally performs, plus PeplowPC branding).
set -euo pipefail
: "${PAYLOAD_REF:?}"

log() { printf '\n==> %s\n' "$*"; }

log "EFI boot files for the ISO"
if compgen -G "/usr/lib/efi/*/*/EFI" >/dev/null; then
    mkdir -p /boot/efi
    cp -ra /usr/lib/efi/*/*/EFI /boot/efi
else
    # Some images ship shim straight into /boot/efi instead (see osbuild/bootc-foundry).
    dnf5 reinstall -y shim-x64 && dnf5 clean all
fi
ls /boot/efi/EFI

log "Installer identity (shown as \"PEPLOWPC OS 45 INSTALLATION\")"
OSR=/usr/lib/os-release
set_osr() {
    if grep -q "^$1=" "$OSR"; then sed -i "s|^$1=.*|$1=\"$2\"|" "$OSR"; else echo "$1=\"$2\"" >>"$OSR"; fi
}
set_osr NAME "PeplowPC OS"
set_osr PRETTY_NAME "PeplowPC OS Installer"
set_osr VARIANT "Installer"
# Selects /etc/anaconda/profile.d/peplowpc.conf (stylesheet, hidden screens).
set_osr VARIANT_ID "peplowpc-installer"
set_osr HOME_URL "https://peplowpc.com/"

log "What to install: the signed PeplowPC OS image embedded in the ISO"
sed "s|@PAYLOAD_REF@|${PAYLOAD_REF}|g" /usr/share/anaconda/interactive-defaults.ks.in \
    >/usr/share/anaconda/interactive-defaults.ks
rm /usr/share/anaconda/interactive-defaults.ks.in
cat /usr/share/anaconda/interactive-defaults.ks

log "Branding fallback"
# Our profile loads peplowpc.css. If profile detection ever fails, Fedora's stylesheet loads
# instead; replacing the images it points at keeps the Fedora logo out either way.
PIX=/usr/share/anaconda/pixmaps
for f in sidebar-bg.png sidebar-logo.png topbar-bg.png; do
    [[ -e "$PIX/$f" ]] && cp -v "$PIX/peplowpc/$f" "$PIX/$f"
done
for f in "$PIX"/*/sidebar-logo.png "$PIX"/*/sidebar-bg.png "$PIX"/*/topbar-bg.png; do
    [[ -e "$f" && "$f" != "$PIX"/peplowpc/* ]] && cp -v "$PIX/peplowpc/$(basename "$f")" "$f"
done

log "Installer environment (normally done by lorax)"
echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >>/etc/passwd
echo "install::14438:0:99999:7:::" >>/etc/shadow
passwd -d root
mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives
mkdir -p /etc/anaconda.repos.d
for d in /usr/share/dnf5/repos.d /etc/yum.repos.d; do
    [[ -d "$d" ]] && find "$d" -maxdepth 1 -name '*.repo' -exec mv -t /etc/anaconda.repos.d/ {} +
done
ln -sf /lib/systemd/system/anaconda.target /etc/systemd/system/default.target
rm -fv /usr/lib/systemd/system-generators/systemd-gpt-auto-generator
ln -sf /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service
mkdir -p "$(realpath /root)"

log "Boot splash"
cp -n /usr/share/plymouth/themes/spinner/*.png /usr/share/plymouth/themes/peplowpc/
plymouth-set-default-theme peplowpc

log "Installer initramfs"
kernel="$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version')"
DRACUT_NO_XATTR=1 dracut --force --zstd --reproducible --no-hostonly \
    --add "anaconda dmsquash-live plymouth" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

log "Installer image ready (payload: ${PAYLOAD_REF})"
