# Open decisions

Each needs an owner call before the phase listed. Record the answer and the date.
"Baseline" is what the scaffold does today.

## Phase 0

1. **Product name.** Working name "PeplowPC OS". As with the browser, something with a story may fit the brand better. Decide before the boot splash and installer artwork are final.
2. **Where the image lives.** Baseline: `ghcr.io/danvillian/peplowpc-os` (personal GitHub account). Option: a `peplowpc` GitHub organization, which keeps the business separate from personal projects and survives a change of maintainer. Changing later means every installed computer must switch image names once, so decide before anyone outside a test VM installs it. The repo and image must be **public** so computers can download updates without a password.
3. **Default browser until PeplowPC Browser runs on Linux.** Baseline: Fedora's Firefox with PeplowPC policies (part of the signed image, updated daily, no extra trust). Options: a) baseline; b) ungoogled-chromium from Flathub with the PeplowPC Browser policy file through its policy extension point (closer to the brand, but a community package and probably not on the verified-only list); c) build PeplowPC Browser for Linux and bake it into the image (the real answer, Phase 2).
4. **DNS-over-TLS strictness and Wi-Fi login pages.** Baseline: `opportunistic`, with `Domains=~.` so every lookup goes to Quad9 rather than the router. Strict (`yes`) cannot be silently downgraded by a hostile network. Caveat found in review: many hotel and airport networks block outside DNS until you log in, and with `~.` the login page may never appear, even in opportunistic mode. Test on a real captive portal in Phase 0. If it fails, options: a) a captive-portal helper that briefly allows the network's own DNS until login completes (Phase 2, also unlocks strict mode); b) drop `~.` so router DNS is used alongside Quad9 (works everywhere, leaks lookups to the network). Recommendation: a.

## Phase 1

5. **Connectivity check.** NetworkManager asks `fedoraproject.org` every few minutes whether the internet works; this is how Wi-Fi login pages pop up. It reveals the IP address to Fedora. Options: a) keep (baseline); b) a PeplowPC-hosted check (PeplowPC would see user IP addresses, which conflicts with "no tracking" on the website unless logs are off); c) off (no login page pop-ups; bad for non-technical users).
6. **Flathub verified only.** Baseline: on. Some well-known apps are not verified (community packages of proprietary apps such as Zoom or Spotify). Options: keep strict and add specific exceptions on request, or allow all of Flathub with a warning.
7. **Disk encryption.** Baseline: the installer offers "Encrypt my data" but does not force it. A stolen laptop without encryption gives away everything. Options: a) baseline; b) force encryption in the kickstart (user must invent and remember a second password); c) encryption plus TPM2 automatic unlock (no extra password, protected against disk removal; needs testing with Secure Boot updates). Recommendation: c, Phase 2; until then, make "Encrypt my data" step one of the install guide.
8. **Kernel hardening cost.** `init_on_free=1` costs about 1 to 5% speed. Also: `lockdown=integrity` would block unsigned kernel modules (stronger, but stops NVIDIA's proprietary driver and VirtualBox). Baseline: init_on_free on, lockdown left to Secure Boot's automatic setting.
9. **Update policy.** Baseline: download daily, apply at the next restart, never force. Gap: people who never restart never update. Options: a GNOME notification after 3 days ("Restart to finish updating, it takes about a minute"), escalating after 7. Phase 2 item.
10. **GNOME Software reviews.** Fetches ratings from `odrs.gnome.org` (sends the app being viewed). Options: keep (useful for choosing apps) or turn off.
11. **Video codecs.** Baseline: Fedora's codecs only (no RPM Fusion). Flatpak apps bring their own codecs, and Firefox handles H.264 through Cisco's OpenH264. Adding RPM Fusion means trusting another package source.
12. **NVIDIA graphics.** Baseline: open-source drivers only. The proprietary driver needs extra signed kernel modules (Universal Blue publishes NVIDIA base images). Decide based on the hardware PeplowPC clients actually have.
13. **License for PeplowPC code.** Apache-2.0 (common for bootc image repos), MIT, or match the browser decision.
14. **Signing key custody.** Private key in the GitHub secret plus a password manager. Who else can access it, how it is rotated, and what to do if it leaks (publish a new `cosign.pub` in an image signed with the old key, before revoking it). Write this down before the first public install.

## Later

15. **Shell theme.** GNOME Shell only takes accent colors from a fixed list; baseline uses green. A full PeplowPC Shell theme (lime) means maintaining CSS against each GNOME release.
16. **Image size and download speed.** "Rechunking" the image makes updates download only what changed. Worth adding once there are real users on slow connections.
17. **Managed fleet for clients.** Small-business clients may want central settings (locked browser policies, required encryption). Probably a second image variant (`peplowpc-os-business`) built from the same repo.

## Decided

| Date | Item | Decision |
|---|---|---|
| 2026-11-05 | Audience | Everyday non-technical people |
| 2026-11-05 | Base | Fedora Atomic (Silverblue) with bootc, Fedora 45 |
| 2026-11-05 | Desktop | GNOME |
| 2026-11-05 | Build | GitHub Actions; daily image build; ISO on demand |
| 2026-11-05 | Default browser (D3) | Firefox with PeplowPC policies stays until a true Linux build of PeplowPC Browser (own patches and branding) passes testing. No interim ungoogled-chromium swap. Needs a Linux build pipeline in the browser project first. |
| 2026-11-05 | Disk encryption (D7) | On by default in the installer (kickstart `autopart --encrypted`, passphrase asked on the disk screen). Not hard-forced, because blocking at the end of an install is worse for users; the baseline check flags unencrypted installs. TPM2 unlock still planned. |
| 2026-11-06 | App menu | P button in the top-left replaces Activities: ArcMenu v70.0 (Windows 11 layout, Super key opens it), vendored in `vendor/arcmenu` and pinned by checksum. Not in Fedora's repos, so it is updated by hand each GNOME release. |
| 2026-11-06 | Installer name | Keep "anaconda bluesky" for internal testing; add `/.buildstamp` before any ISO goes to someone else. |
| 2026-11-05 | Secure Boot on Hyper-V | Fedora 45 boots with Secure Boot on using the "Microsoft UEFI Certificate Authority" template (verified). |
