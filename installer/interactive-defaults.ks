# PeplowPC OS installer defaults. @PAYLOAD_REF@ is filled in by build-installer.sh.

# Install the signed PeplowPC OS image embedded in the ISO (no download needed). Afterwards the
# system follows the same image online; peplowpc-update turns on signature checking at first boot.
bootc --source-imgref containers-storage:@PAYLOAD_REF@ --target-imgref @PAYLOAD_REF@

# Encrypt the disk by default (DECISIONS D7). No passphrase is stored here: the installer asks for one
# on the disk screen. No clearpart, so existing data on the disk is never wiped without the user choosing it.
autopart --type=btrfs --encrypted --luks-version=luks2

# Leave the firewall exactly as the image ships it (Anaconda otherwise adds SSH to the default zone).
firewall --use-system-defaults

%post --log=/root/peplowpc-post.log
echo "Installed from @PAYLOAD_REF@"
# Backup for the firewall line above: drop any installer-written copy of our zone so the image's applies.
rm -fv /etc/firewalld/zones/peplowpc.xml /etc/firewalld/zones/peplowpc.xml.old
firewall-offline-cmd --zone=peplowpc --list-services
%end
