# Roadmap

Start small, ship something real, then add features. Each phase ends with something a person can install and use.

## Phase 0: Prove the image (days)

Goal: a signed image builds every day, installs in a VM, and every line in `SECURITY-BASELINE.md` is checked.

**Build**
- [x] Repo scaffold: Containerfile, build script, hardening files, branding, CI, docs (2026-11-05).
- [x] One-time setup done (`BUILD.md`): GitHub repo, cosign key pair, `SIGNING_SECRET`, package made public.
- [x] First green run of `build.yml`: image signed, verified with cosign and with the installed-system policy check, `:stable` moved.
- [x] `glib-compile-schemas --strict` passes against Fedora 45 / GNOME 51 schemas (catches renamed settings).
- [x] First ISO from `build-iso.yml` (2026-11-06).

**Install and first boot (Hyper-V Gen 2, Secure Boot on)**
- [x] Installer asks for an encryption passphrase by default (2026-11-06).
- [ ] **Boot splash fix** (changed 2026-11-06: logo .62, spinner .82; verify on next install): on the disk-unlock screen the PeplowPC logo overlaps the passphrase prompt text and keyboard icon (photo 2026-11-06). Move the logo down: `WatermarkVerticalAlignment=.45` to about `.70` in `system_files/usr/share/plymouth/themes/peplowpc/peplowpc.plymouth`, and check it on both the normal boot and the unlock screen.
- [ ] **Before giving an ISO to anyone else:** add `/.buildstamp` to the installer image (Product, Version, IsFinal=True) so the installer says "PeplowPC OS 45" instead of "anaconda bluesky" and drops the red "PRE-RELEASE / TESTING" label. Kept as is for internal testing (decision 2026-11-06).
- [ ] **First boot on real hardware with SELinux enforcing** (Dell XPS 13 9300, 2026-11-06): boot stopped at text because installer-written files in /etc were unlabeled (polkit and GDM failed). Fixed by `peplowpc-relabel.service`; verify on the next fresh install that it boots straight to GNOME setup with no `enforcing=0`.
- [ ] **Disk-unlock prompt invisible on the XPS 13** (graphical splash did not appear before the prompt; typing blind worked). Investigate: likely Plymouth starting before the Intel graphics driver; try adding `i915` to the initramfs or `plymouth.use-simpledrm`.
- [ ] **Firmware boot entry says "Fedora"** in the Dell boot menu (copied from Fedora's EFI files). Rename to PeplowPC OS.
- [ ] **P app menu** (added 2026-11-06, ArcMenu v70.0): P button top-left, Windows 11 layout, Super key opens it, pinned apps all launch, no ArcMenu pop-ups, `check-baseline.sh` passes "P app menu enabled".
- [ ] **Settings > About** shows the PeplowPC wordmark, not Fedora's (build.sh replaces the logo files compiled into GNOME Settings; check light and dark mode).
- [ ] **Branded installer** (built 2026-11-06: `installer/Containerfile`, image-builder `generic-iso`; verify on next install): no Fedora logo or blue anywhere, lime buttons, encryption default still asked, firewall without SSH, offline install works, **SELinux enforcing** (first branded install on 2026-11-06 inherited `selinux=0` from the installer; fixed in the installer profile), PeplowPC splash and one passphrase prompt at boot (`rhgb quiet` now in kargs.d), GNOME setup skips the privacy page (location stays off).
- [x] GNOME first-boot setup creates the user account.
- [x] Signed updates: after one restart `sudo rpm-ostree status` shows `ostree-image-signed:`, and it stays that way after `sudo peplowpc-update` plus another restart. (First test 2026-11-05 found a plain `bootc upgrade` undid it; fixed with `peplowpc-update`.)
- [x] `peplowpc-flatpak-setup` installed every starter app; `flatpak remotes` shows only `flathub-verified`.
- [ ] Branding: boot splash, login logo, wallpaper, lime accent in apps, Settings > About shows PeplowPC OS.

**Verify the baseline** (`tools/check-baseline.sh`: 71 passed, 0 failed on a fresh install, 2026-11-06)
- [x] `sysctl` values, blocked modules (`modprobe dccp` fails).
- [x] Kernel args present on a **fresh install** (`cat /proc/cmdline`). The installer may skip `kargs.d`, and bootc only applies changes between versions, so a miss here is permanent for that machine. If missing, add them to the kickstart in `disk_config/iso.toml` (`bootloader --append`).
- [ ] Firewall: `firewall-cmd --get-default-zone` is `peplowpc`; port scan from another VM finds nothing open.
- [x] DNS: `resolvectl status` shows Quad9 with DNSOverTLS; router DNS not used (see SECURITY-BASELINE note).
- [x] Time: `chronyc -N authdata` shows NTS for all sources.
- [ ] Wi-Fi MAC randomization (needs a USB Wi-Fi adapter passed to a VM, or a spare laptop).
- [ ] Firefox: `about:policies` shows all policies active; uBlock Origin installed; GPC on.
- [ ] Idle network audit, 300 s: only the hosts in "Expected outbound connections".
- [ ] **Update test:** push a trivial change, wait for the build, confirm the VM downloads it in the background and applies it at restart. Then `sudo bootc rollback` and confirm the old version boots.
- [ ] **Tamper test:** sign a test image with a different key, point the VM at it, confirm the update is refused.
- [ ] Everyday-use check: printer discovery, a video call in Firefox, USB stick, Bluetooth headset, hotel-style captive portal.
- [ ] Settle the open items in `DECISIONS.md` marked "Phase 0".

## Phase 1: First real install (weeks)

Goal: something you would put on a client's or family member's laptop.

- [ ] Install on real hardware (a spare laptop): Wi-Fi, sleep and resume, battery, webcam, fingerprint reader.
- [ ] Install guide in plain English (USB stick creation from Windows, the encryption checkbox, first-boot screens), in the website's voice.
- [ ] Decisions D5 to D14 settled.
- [ ] Release channel naming: `stable` for users, `testing` built from a branch for you.
- [ ] Build failure alerting (email or phone notification when the daily build fails).
- [ ] ISO hosted somewhere durable (GitHub Releases or peplowpc.com), with SHA256SUMS and a signature.
- [ ] Shell theme decision (D15) and, if yes, first version.

## Phase 2: PeplowPC touches (months)

- [ ] **PeplowPC Browser for Linux** baked into the image as the default browser (shares patches and policies with the Windows build).
- [ ] **Welcome app**: a short first-run tour in plain English: what is protected, how updates work, how to get help. Bricolage headings, lime accents.
- [ ] **"Is this a scam?" helper** tied to the Outsmart the Scammers and Phish Fry material.
- [ ] Restart reminders for staged updates (D9).
- [ ] Encryption with TPM2 automatic unlock (D7).
- [ ] Captive-portal helper, then strict DNS-over-TLS (D4).
- [ ] Rechunked images for smaller update downloads (D16).
- [ ] Automated VM test in CI: boot the new image, run the baseline checks, block publishing on failure.

## Phase 3: Clients and business (later)

- [ ] `peplowpc-os-business` variant: locked policies, required encryption, remote-help tooling chosen with clients (D17).
- [ ] PeplowPC support channel built into the OS ("Get help from PeplowPC").
- [ ] Hardware recommendations list (laptops tested with PeplowPC OS).
