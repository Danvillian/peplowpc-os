# ArcMenu (vendored)

The PeplowPC app menu (P button in the top-left corner, Windows 11 style layout) is ArcMenu,
a GNOME Shell extension. It is not packaged in Fedora, so the exact upstream release is kept here
and built into the image by the `arcmenu` stage of `Containerfile`.

| | |
|---|---|
| Upstream | https://gitlab.com/arcmenu/ArcMenu |
| Version | v70.0 (supports GNOME Shell 45 to 51) |
| File | `ArcMenu-v70.0.tar.gz`, downloaded from `https://gitlab.com/arcmenu/ArcMenu/-/archive/v70.0/ArcMenu-v70.0.tar.gz` on 2026-11-06 |
| Checksum | `SHA256SUMS` (the build fails if it does not match) |
| License | GPL-2.0-or-later (see `LICENSE` inside the archive). Shipping this source next to the build satisfies the GPL. |
| Network | Reviewed 2026-11-06: no network calls. Its "update notifier" is a local pop-up only; PeplowPC turns it off. |

PeplowPC settings for it (layout, P icon, pinned apps, Super key) are in
`system_files/usr/share/glib-2.0/schemas/zz0-peplowpc.gschema.override`, section `org.gnome.shell.extensions.arcmenu`.

## Updating (each GNOME release, about twice a year)

1. Check the new ArcMenu release lists the new GNOME version in `metadata.json` (`shell-version`).
2. Download the new tag's `.tar.gz` from GitLab into this folder and delete the old one.
3. `sha256sum ArcMenu-vNN.N.tar.gz > SHA256SUMS`
4. Change `ARCMENU_VERSION` in `Containerfile`.
5. Build, install in a VM, run `tools/check-baseline.sh` (checks the menu is enabled), and click through the menu.

If a GNOME update ever arrives before a compatible ArcMenu, GNOME disables the extension and the
normal Activities button comes back. Nothing else breaks.
