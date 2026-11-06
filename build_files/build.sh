#!/usr/bin/bash
# PeplowPC OS image build. Runs once inside the Containerfile, as root, on top of Fedora Silverblue.
# Every change here should have a matching line in docs/SECURITY-BASELINE.md explaining why.
set -euo pipefail

CTX=/ctx
: "${FEDORA_VERSION:?}" "${IMAGE_NAME:?}" "${IMAGE_REGISTRY:?}" "${IMAGE_TAG:?}" "${IMAGE_VERSION:?}"
IMAGE_REF="${IMAGE_REGISTRY,,}/${IMAGE_NAME}"

log() { printf '\n==> %s\n' "$*"; }

remove_if_installed() {
    local present=()
    for pkg in "$@"; do
        rpm -q "$pkg" >/dev/null 2>&1 && present+=("$pkg")
    done
    if ((${#present[@]})); then
        dnf5 -y remove --no-autoremove "${present[@]}"
    fi
}

# --------------------------------------------------------------------------------------------
log "Copy PeplowPC system files"
cp -a "$CTX/system_files/." /
chmod 0755 /usr/libexec/peplowpc/*

# --------------------------------------------------------------------------------------------
log "Packages"
# jq: used by build steps and first-boot scripts.
# firefox: the default browser lives in the signed image (DECISIONS D3), so make sure it is there.
dnf5 -y install jq firefox
# Crash reporters upload data off the machine. Not shipped (see SECURITY-BASELINE, Telemetry).
remove_if_installed abrt abrt-desktop abrt-gui gnome-abrt
dnf5 clean all

# --------------------------------------------------------------------------------------------
log "Identity: os-release"
# ID stays "fedora" on purpose: bootc-image-builder and other tools pick their settings from it.
OSR=/usr/lib/os-release
set_osr() { # key value
    if grep -q "^$1=" "$OSR"; then
        sed -i "s|^$1=.*|$1=\"$2\"|" "$OSR"
    else
        echo "$1=\"$2\"" >>"$OSR"
    fi
}
set_osr NAME "PeplowPC OS"
set_osr PRETTY_NAME "PeplowPC OS (based on Fedora ${FEDORA_VERSION})"
set_osr VARIANT "PeplowPC"
set_osr VARIANT_ID "peplowpc"
set_osr LOGO "peplowpc-logo"
set_osr HOME_URL "https://peplowpc.com/"
set_osr SUPPORT_URL "https://peplowpc.com/contact.html"
set_osr BUG_REPORT_URL "https://github.com/Danvillian/peplowpc-os/issues"
set_osr DEFAULT_HOSTNAME "peplowpc"
set_osr IMAGE_ID "${IMAGE_NAME}"
set_osr IMAGE_VERSION "${IMAGE_VERSION}"
# Fedora's documentation links would confuse PeplowPC users; drop them.
sed -i '/^DOCUMENTATION_URL=/d' "$OSR"

jq -n --arg ref "$IMAGE_REF" --arg tag "$IMAGE_TAG" --arg ver "$IMAGE_VERSION" --arg fedora "$FEDORA_VERSION" \
    '{"image-ref": $ref, "image-tag": $tag, "version": $ver, "fedora-version": $fedora}' \
    >/usr/share/peplowpc/image-info.json

# --------------------------------------------------------------------------------------------
log "Update trust: only accept PeplowPC images signed with our key"
POLICY=/etc/containers/policy.json
POLICY_SRC="$POLICY"
[[ -f "$POLICY_SRC" ]] || POLICY_SRC=/usr/share/containers/policy.json
if [[ -s "$CTX/keys/cosign.pub" ]]; then
    install -Dm0644 "$CTX/keys/cosign.pub" /etc/pki/containers/peplowpc.pub
    # Default must be "reject" or bootc refuses --enforce-container-sigpolicy.
    # Other registries stay usable for podman/toolbox through the explicit "" entries.
    jq --arg ref "$IMAGE_REF" '
        .default = [{"type": "reject"}]
        | .transports.docker[$ref] = [{
            "type": "sigstoreSigned",
            "keyPath": "/etc/pki/containers/peplowpc.pub",
            "signedIdentity": {"type": "matchRepository"}
          }]
        | .transports.docker[""] = [{"type": "insecureAcceptAnything"}]
        | .transports["docker-daemon"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["containers-storage"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["oci"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["oci-archive"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["docker-archive"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["dir"][""] = [{"type": "insecureAcceptAnything"}]
    ' "$POLICY_SRC" >/tmp/policy.json
    install -Dm0644 /tmp/policy.json "$POLICY"
    install -d /etc/containers/registries.d
    cat >/etc/containers/registries.d/peplowpc.yaml <<EOF
docker:
  ${IMAGE_REF}:
    use-sigstore-attachments: true
EOF
else
    echo "WARNING: cosign.pub not found. This image will not verify its own updates."
    echo "         Fine for a local test build. CI builds must include cosign.pub."
    rm -f /etc/containers/registries.d/peplowpc.yaml
fi

# --------------------------------------------------------------------------------------------
log "Telemetry off"
systemctl mask rpm-ostree-countme.timer || true
shopt -s nullglob
for repo in /etc/yum.repos.d/*.repo /usr/share/dnf5/repos.d/*.repo; do
    sed -i 's/^countme=.*/countme=0/' "$repo"
done
shopt -u nullglob

# --------------------------------------------------------------------------------------------
log "Firewall: PeplowPC zone (block incoming, allow printer discovery and IPv6 setup)"
FWCONF=/etc/firewalld/firewalld.conf
[[ -f "$FWCONF" ]] || FWCONF=/usr/lib/firewalld/firewalld.conf
sed -i 's/^DefaultZone=.*/DefaultZone=peplowpc/' "$FWCONF"
grep -q '^DefaultZone=peplowpc' "$FWCONF"

# --------------------------------------------------------------------------------------------
log "Browser defaults (Firefox until PeplowPC Browser ships for Linux, see DECISIONS D3)"
FFFILES="$(rpm -ql firefox)"
FFDIR="$(dirname "$(grep -m1 -E '/firefox/application\.ini$' <<<"$FFFILES")")"
[[ -f "$FFDIR/application.ini" ]] || { echo "Firefox install folder not found" >&2; exit 1; }
install -Dm0644 /usr/share/peplowpc/firefox-policies.json "$FFDIR/distribution/policies.json"

# --------------------------------------------------------------------------------------------
log "Desktop defaults"
# Fedora has used both names for the Firefox launcher; pin the dock to whichever exists.
SCHEMA=/usr/share/glib-2.0/schemas/zz0-peplowpc.gschema.override
if [[ ! -f /usr/share/applications/org.mozilla.firefox.desktop && -f /usr/share/applications/firefox.desktop ]]; then
    sed -i "s/'org.mozilla.firefox.desktop'/'firefox.desktop'/" "$SCHEMA"
fi
glib-compile-schemas --strict /usr/share/glib-2.0/schemas
gtk-update-icon-cache -f /usr/share/icons/hicolor || true

# --------------------------------------------------------------------------------------------
log "Boot splash"
# The two-step plugin needs spinner frames and password-prompt images (used for disk encryption).
# Borrow them from Fedora's spinner theme; our watermark.png stays.
cp -n /usr/share/plymouth/themes/spinner/*.png /usr/share/plymouth/themes/peplowpc/
plymouth-set-default-theme peplowpc
KVER="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -n1)"
dracut --no-hostonly --kver "$KVER" --reproducible --zstd --add ostree -f "/usr/lib/modules/$KVER/initramfs.img"
chmod 0600 "/usr/lib/modules/$KVER/initramfs.img"

# --------------------------------------------------------------------------------------------
log "Services"
systemctl enable \
    peplowpc-flatpak-setup.timer \
    peplowpc-flatpak-update.timer \
    peplowpc-signed-switch.timer \
    bootc-fetch-apply-updates.timer \
    firewalld.service \
    chronyd.service
# Fedora's own Flatpak remote is replaced by Flathub (verified apps only) in peplowpc-flatpak-setup.
systemctl disable flatpak-add-fedora-repos.service 2>/dev/null || true
# rpm-ostree's own update timer would race bootc's; bootc owns updates.
systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true

log "Done: ${IMAGE_REF}:${IMAGE_TAG} (${IMAGE_VERSION})"
