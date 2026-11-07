# Architecture

## Layers

```
+-----------------------------------------------------------+
| User layer: Flatpak apps (Flathub, verified only), files   |  /var, /home   (changeable, kept across updates)
+-----------------------------------------------------------+
| PeplowPC layer: hardening, privacy, branding, services     |  /usr, /etc    (built into the image)
+-----------------------------------------------------------+
| Fedora Silverblue 45: kernel, GNOME 51, systemd, SELinux   |  /usr          (read-only at runtime)
+-----------------------------------------------------------+
```

PeplowPC OS is a **bootable container image**. The `Containerfile` starts from Fedora's Silverblue image and runs
`build_files/build.sh`, which copies `system_files/` into place and makes a handful of changes that cannot be
done with plain files (os-release, signing policy, boot splash, firewall default). The result is pushed to
GitHub Container Registry and signed.

A PeplowPC OS computer does not install updates package by package. It downloads the whole new image,
prepares it next to the running one, and switches on the next restart. The previous version stays on disk.

### What lives where

| Path | At runtime | Who changes it |
|---|---|---|
| `/usr` | Read-only | Only a new image. Malware running as admin still cannot change it without a reboot into a new image. |
| `/etc` | Writable | Image provides defaults; local changes are kept and merged on update (three-way merge). |
| `/var`, `/home` | Writable | User data, Flatpak apps, logs. Never touched by an update. |

That is why PeplowPC defaults live in `/usr` wherever the software allows it (`/usr/lib/sysctl.d`,
`/usr/lib/NetworkManager/conf.d`, `/usr/lib/systemd/resolved.conf.d`, the GNOME schema override).
Only a few files must live in `/etc` (`chrony.conf`, container signing policy, `/etc/skel`).

## Update flow

```
GitHub Actions (daily 09:17 UTC)
  pull quay.io/fedora-ostree-desktops/silverblue:45   (Fedora's latest security fixes)
  build Containerfile, run `bootc container lint`
  push ghcr.io/danvillian/peplowpc-os:stable (+ :stable-YYYYMMDD, :45)
  cosign sign with the PeplowPC key, then verify the signature
        |
        v
PeplowPC OS computer
  bootc-fetch-apply-updates.timer
    peplowpc-update   (makes sure updates are signed-only, then bootc upgrade: downloads, checks the
                       signature against /etc/pki/containers/peplowpc.pub, stages)
  next restart -> new version
  problem? -> pick the previous entry in the boot menu, or `sudo bootc rollback`
```

Apps update separately through `peplowpc-flatpak-update.timer` (every 6 hours) and GNOME Software.

### Update discipline

- **A build that stops is a security problem.** If the daily build fails, users stop getting Fedora fixes.
  Watch the Actions tab; a failure older than 48 hours is an incident.
- **No release ships without updates working.** Every Phase 1 test includes an update from one image to the next.
- **Fedora version upgrades** (45 to 46, about every six months) are a one-line change to `FEDORA_VERSION`,
  tested on a VM first. Fedora supports each release for about 13 months, so there is no rush.

## Signing chain

1. You create a key pair once with `cosign generate-key-pair`. The private key goes into the GitHub secret
   `SIGNING_SECRET` and your password manager. The public key is committed as `keys/cosign.pub`.
2. CI pushes a dated tag, signs that exact digest, then checks it twice: with `cosign verify`, and with
   `skopeo copy` using the policy file baked into the image (the same check an installed system makes).
   Only then does `:stable` move, by copying the signed manifest. A failure part-way leaves `:stable` on the
   last good build, so installed systems never see an unsigned update.
3. CI uses **cosign v2** on purpose. cosign v3 stores signatures in a newer bundle format that the system's
   update tooling does not read yet; signing with it would pass CI and be refused by every installed computer.
   Do not accept a Dependabot or manual upgrade to cosign v3 without re-testing the update path.
4. `build.sh` installs `keys/cosign.pub` into the image as `/etc/pki/containers/peplowpc.pub` and writes a container
   policy that **rejects** anything not covered by an explicit rule, and requires a PeplowPC signature for the
   PeplowPC image.
5. The installer cannot know our key in advance, so a fresh install starts in "unverified" mode.
   `peplowpc-update` (run 3 minutes after every boot, every 6 hours, and by the daily update timer) checks
   which image the next restart will use. If it is not the signed PeplowPC image, it runs
   `bootc switch --enforce-container-sigpolicy`. It checks real state every time rather than a one-time
   marker, because a plain `bootc upgrade` run before the first restart replaces the queued signed
   deployment with an unverified one (found in testing, 2026-11-05). From then on, every update must carry
   our signature. Admins should use `sudo peplowpc-update`, never plain `bootc upgrade`.

If the private key leaks, an attacker could sign a malicious update. Key custody is DECISIONS D14.

## First boot

```
Installer: disk only ("Encrypt my data" offered)
  -> first boot: GNOME setup (language, keyboard, privacy, Wi-Fi, user account)
  -> background, by timer, so login is never delayed:
       peplowpc-signed-switch     (3 min, then every 6 h)  require signed updates (peplowpc-update --ensure-signed)
       peplowpc-flatpak-setup     (2 min)  Flathub (verified only) + starter apps; retries hourly,
                                           gives up on an unavailable app after about a day
```

## Installer

The installer ISO is built from its own small container image, `installer/Containerfile`:

```
quay.io/fedora/fedora-bootc:45
  + Anaconda installer, boot media tools, PeplowPC boot splash
  + installer/files/: Anaconda profile (PeplowPC stylesheet, hides account/network/time screens),
                      artwork, ISO boot menu (iso.yaml)
  + interactive-defaults.ks: install the embedded signed image, encrypt by default,
                             leave the firewall alone
        |
image-builder generic-iso --bootc-installer-payload-ref ghcr.io/danvillian/peplowpc-os:stable
        |
PeplowPC-OS-YYYYMMDD.iso  (offline install: the system image is inside the ISO)
```

This follows Fedora's current method (image-builder "generic-iso"; bootc-image-builder is deprecated).
The older `anaconda-iso` path is still available as a fallback (`builder: legacy` in the ISO workflow,
config in `disk_config/iso.toml`). It works but looks like Fedora's installer.

Anaconda copies some boot settings from the installer into the installed system. The installer runs with
`selinux=0`, so the PeplowPC installer profile (`installer/files/etc/anaconda/profile.d/peplowpc.conf`)
removes `selinux` and `console` from that list. Without this, every install had SELinux switched off
(found in testing 2026-11-06; `tools/check-baseline.sh` now checks SELinux is enforcing).

Known upstream issue: a bootc system installed through Anaconda logs a failed
`systemd-remount-fs.service` at boot (Fedora atomic-desktops tracker #72). Harmless so far; watch it.

## Third-party code in the image

Everything in the image comes from Fedora's signed packages, except:

| What | Where | Why | Kept current by |
|---|---|---|---|
| ArcMenu (P app menu) | `vendor/arcmenu/`, built in the `arcmenu` stage of `Containerfile` | Not packaged by Fedora | Hand update each GNOME release (`vendor/arcmenu/README.md`); checksum-pinned |

## Why Fedora Atomic

| | Fedora Atomic + bootc (chosen) | Debian live-build | Arch |
|---|---|---|---|
| Updates for non-technical users | Whole-image, automatic, one-click rollback | Package by package, can break halfway | Manual, frequent breakage |
| Tampering resistance | `/usr` read-only | Writable | Writable |
| Secure Boot | Fedora-signed kernel | Debian-signed kernel | Manual |
| SELinux | Enforcing by default | AppArmor | None by default |
| Our build | One `Containerfile`, built by GitHub Actions | Custom ISO pipeline | Custom ISO pipeline |
| Proven by | Bluefin, Bazzite, secureblue | Kicksecure | |
