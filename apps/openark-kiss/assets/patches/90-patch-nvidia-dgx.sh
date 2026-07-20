#!/usr/bin/env bash
# Copyright (c) 2026 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Apply specialized settings
# Patch NVIDIA DGX devices

# Prehibit errors
set -e -o pipefail
# Verbose
set -x

# Filter nodes
if ! [ -f '/sys/class/dmi/id/product_family' ] || [ "x$(cat '/sys/class/dmi/id/product_family')" != 'xDGX Spark' ]; then
    exit
fi

# Enable watchdog kernel module
# NOTE: https://forums.developer.nvidia.com/t/dgx-spark-keeps-rebooting-every-20-30-minutes/350692/6
sudo apt remove -y linux-generic "linux-headers-6.8.0-*" linux-headers-generic "linux-image-6.8.0-*" linux-image-generic "linux-modules-6.8.0-*" "linux-modules-extra-6.8.0-*"

# Subiquity also runs this patch inside the target chroot. Runtime
# NetworkManager operations belong to the commissioned system after first boot.
if systemd-detect-virt --quiet --chroot; then
    exit
fi

# Enable wireless networking
nmcli radio wifi on

# Do not warm-reboot a DGX Spark from commissioning. Some firmware/OS
# combinations lose the Realtek RJ-45 device after a warm reboot and recover
# only after a full power cycle. Keeping the active wired link is more important
# than forcing optional Wi-Fi discovery here.
# NOTE: https://forums.developer.nvidia.com/t/ethernet-does-not-come-up-after-reboot-after-latest-update/361628
