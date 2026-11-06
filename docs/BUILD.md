# Building and testing

GitHub Actions does the building. You do not need a Linux machine to produce images or the installer.
Keep this on hardware and accounts you own, not Watchfire's (same rule as the browser build).

## One-time setup

1. **Create the repo.** On GitHub, create a **public** repository `peplowpc-os` (under `Danvillian`, or a
   `peplowpc` organization if you decide that in DECISIONS D2). Push this folder to it.

2. **Create the signing key.** cosign is a separate program, installed once. In PowerShell:

   ```powershell
   winget install --id Sigstore.Cosign --exact --version 2.6.1
   ```

   Version 2.x matches the cosign the GitHub build uses. Pin it so `winget upgrade --all` does not move
   it to 3.x: `winget pin add --id Sigstore.Cosign`.

   winget installs the command as **`cosign-windows-amd64`**, not `cosign`. Open a new PowerShell window,
   then create the keys inside the `keys` folder (press Enter twice for no password):

   ```powershell
   cd keys
   cosign-windows-amd64 version
   cosign-windows-amd64 generate-key-pair
   ```

   Press Enter twice for no password (CI needs to use it unattended). This creates `cosign.key` (private) and
   `cosign.pub` (public).

3. **Store the private key.**
   - Copy the whole contents of `cosign.key` into a new repository secret named `SIGNING_SECRET`
     (repo Settings > Secrets and variables > Actions > New repository secret).
   - Save `cosign.key` in your password manager.
   - Delete `keys/cosign.key` from the folder. `.gitignore` already blocks it, but do not leave it lying around.

4. **Commit the public key and mark scripts executable.** Windows does not record the "executable" flag, so set it in git once:

   ```powershell
   git add keys/cosign.pub
   git update-index --add --chmod=+x build_files/build.sh tools/build-local.sh tools/audit-network.sh system_files/usr/libexec/peplowpc/flatpak-setup system_files/usr/libexec/peplowpc/signed-switch
   git commit -m "Add signing key"
   git push
   ```

   The first build starts.

5. **Make the image public.** After the first successful build: your GitHub profile > Packages >
   `peplowpc-os` > Package settings > Change visibility > Public. Computers cannot download updates otherwise.

6. **Turn on notifications** for failed workflow runs (GitHub Settings > Notifications > Actions).

## Building

| What | How |
|---|---|
| System image | Automatic: every push to `main` and daily at 09:17 UTC. By hand: Actions > Build PeplowPC OS image > Run workflow. |
| Installer ISO | Actions > Build PeplowPC OS installer (ISO) > Run workflow. Choose **branded** (default) or **legacy** (fallback, Fedora-looking). Download the `peplowpc-os-iso-...` artifact (kept 7 days). Keep ISOs in `C:\ISO`: Hyper-V cannot read them from OneDrive. |
| Local test build | On Fedora or WSL2 with podman: `tools/build-local.sh` (image), `tools/build-local.sh iso`, or `tools/build-local.sh qcow2`. |

Pull requests build the image but do not publish or sign it.

## Test in Hyper-V

1. Hyper-V Manager > New > Virtual Machine.
   - **Generation 2**.
   - Memory: 4096 MB or more; turn off Dynamic Memory for the first install.
   - Network: a switch with internet access.
   - Disk: 64 GB.
   - Install from the PeplowPC OS ISO.
2. Before starting: VM Settings > Security > Secure Boot **on**, template **Microsoft UEFI Certificate Authority**
   (the default "Microsoft Windows" template refuses Linux).
3. Processor: 2 or more virtual processors.
4. Start, install with "Encrypt my data" ticked, finish GNOME setup, wait a few minutes with networking on
   for the starter apps and signed-update switch, then restart once.
5. Run the baseline check inside the VM (as your normal user, it asks for your password once):

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/Danvillian/peplowpc-os/main/tools/check-baseline.sh
   bash check-baseline.sh
   ```

   It prints PASS or FAIL for every setting in `SECURITY-BASELINE.md`. Then work through the rest of the
   Phase 0 checklist in `ROADMAP.md`. Useful commands:

   ```bash
   sudo rpm-ostree status                 # first line should start with ostree-image-signed:
   sudo peplowpc-update                   # update by hand (never use plain "bootc upgrade")
   systemctl status peplowpc-signed-switch peplowpc-flatpak-setup
   journalctl -b -u peplowpc-flatpak-setup
   flatpak remotes
   firewall-cmd --get-default-zone
   resolvectl status
   chronyc -N authdata
   cat /proc/cmdline
   sudo tools/audit-network.sh 300        # copy the tools folder in first
   ```

The same ISO works on the Scale Computing cluster (UEFI VM with Secure Boot) for longer-running tests.

## Moving to a new Fedora release

1. Change `FEDORA_VERSION` in `.github/workflows/build.yml` (and the default in `Containerfile`).
2. Run the build, install the result in a fresh VM, and update an existing VM to it.
3. Repeat the Phase 0 baseline checks, especially the GNOME schema override (settings get renamed between GNOME releases).
