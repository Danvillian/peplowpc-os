# Branding

Same brand system as peplowpc.com and PeplowPC Browser (`../peplowpc-browser/branding`).

| Token | Value | Used for |
|---|---|---|
| Ink | `#0B0D14` | Backgrounds, boot splash, installer sidebar and top bar, P in the tile |
| Surface | `#141826` / `#1C2133` | Panels |
| Border | `#2A3048` | |
| Cream | `#F4F1EA` | Wordmark and text on dark |
| Muted | `#A9B0C2` | Secondary text, dot grid |
| Lime | `#C6F432` | Accent, the P tile, installer buttons and progress bar |
| Olive | `#4A6200` | Accent text in light mode (lime is unreadable on white) |
| Display font | Bricolage Grotesque | Wordmark (converted to outlines, so the OS does not need the font) |
| UI font | GNOME's Adwaita Sans | Already derived from Inter, the website's UI font |

## Where each asset shows up

| File | Where the user sees it |
|---|---|
| `system_files/usr/share/backgrounds/peplowpc/peplowpc-dots.png` | Default desktop wallpaper |
| `system_files/usr/share/backgrounds/peplowpc/peplowpc-tile.png` | Lock screen; second wallpaper choice |
| `system_files/usr/share/plymouth/themes/peplowpc/watermark.png` | Boot splash and disk-unlock screen (installed system and installer) |
| `system_files/usr/share/pixmaps/peplowpc-gdm-logo.png` | Bottom of the login screen |
| `system_files/usr/share/icons/hicolor/scalable/apps/peplowpc-logo*.svg` | Settings > System > About (from `LOGO=` in os-release) |
| `system_files/etc/skel/.config/gtk-4.0/gtk.css` | Lime buttons, switches and highlights in apps |
| `system_files/usr/share/glib-2.0/schemas/zz0-peplowpc.gschema.override` | Dark mode, wallpaper, dock apps, login logo |
| `installer/files/usr/share/anaconda/pixmaps/peplowpc/` | Installer: sidebar background, sidebar wordmark, top bar, and `peplowpc.css` (colors) |

## Wallpaper safe area

GNOME fills the screen by cropping ("zoom"). On a 4:3 screen only the middle 2880 px of the 3840 px
wallpaper show, so the tile stays inside x 480 to 3360 with a margin. Check new designs at 16:9, 16:10 and 4:3.

## Boot splash layout

`peplowpc.plymouth` positions things as fractions of screen height: disk-unlock prompt at .382,
logo (watermark) at .62, spinner at .82. The logo sat at .45 until 2026-11-06 and overlapped the
passphrase prompt. Plymouth's settings file does not take comments, so notes live here.

## Installer theme

The installer (Anaconda) reads `installer/files/etc/anaconda/profile.d/peplowpc.conf`, which points at
`peplowpc.css`. The stylesheet overrides Anaconda's three branding hooks (`.logo-sidebar`, `.logo`,
`AnacondaSpokeWindow #nav-box`) plus the main button and progress bar colors. The installer's content
area stays light for now; a dark installer is a later item.

## Regenerating

Everything is drawn by `tools/render.py` from the tokens above and the P tile in the browser's `icon.svg`.
Change a token or the tile there, then:

```bash
pip install fonttools uharfbuzz pillow
python3 branding/tools/render.py
```

Review `assets-preview.png` before committing.

`fonts/` holds the website's font files converted to TTF. They are web subsets (Latin only), used only
for rendering; they are not installed into the OS.

## Known gap

GNOME Shell (top bar, quick settings, overview) only offers a fixed list of accent colors, so the shell
uses **green**, the nearest match, while apps get true lime from `gtk.css`. A matching shell theme is a
later item in `docs/ROADMAP.md`.

## Trademark care

Say "based on Fedora". Do not use the Fedora logo or the word "Fedora" in the product name or
marketing artwork (Fedora trademark guidelines). The branded installer exists for this reason.
