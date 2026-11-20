# Interactive install: this kickstart only names the payload (the osyx image
# embedded in the ISO). Disk, user, language, keyboard and time zone are left
# out on purpose, so Anaconda asks for them. Replaces the unattended
# osbuild.ks from bootc-image-builder (clearpart --all + autopart + reboot).
ostreecontainer --url=/run/install/repo/container --transport=oci

%post --erroronfail
set -e
# Track the published image for `bootc upgrade` instead of the local build ref.
# The image ref below is filled in by build-iso.sh (osyx-ublue or osyx-ublue-nvidia).
bootc switch --mutate-in-place --transport registry @TARGET@
%end
