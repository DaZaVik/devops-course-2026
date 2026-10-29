set -e
findmnt -n -o FSTYPE /
cat > /etc/modprobe.d/devops-ext4-only.conf <<'EOF'
# This lab uses ext4 and no MD RAID. Work around VirtualBox/Hyper-V RAID6 AVX2 hang.
install btrfs /bin/false
install raid456 /bin/false
install raid6_pq /bin/false
blacklist btrfs
blacklist raid456
blacklist raid6_pq
EOF
cat > /etc/default/grub.d/99-devops-vbox.cfg <<'EOF'
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX module_blacklist=raid6_pq,raid456,btrfs"
GRUB_DISABLE_OS_PROBER=true
EOF
update-initramfs -u
update-grub
grep module_blacklist /boot/grub/grub.cfg
