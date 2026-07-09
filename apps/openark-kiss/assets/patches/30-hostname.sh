#!/usr/bin/env bash
# Copyright (c) 2025 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Hostname Configuration

# Prehibit errors
set -e -o pipefail
# Verbose
set -x

UUID="$(cat /sys/class/dmi/id/product_uuid)"

if ! grep -qE '^127\.0\.0\.1[[:space:]]+.*localhost' /etc/hosts; then
  echo "127.0.0.1 localhost" >>/etc/hosts
fi
if ! grep -qE '^::1[[:space:]]+.*localhost' /etc/hosts; then
  echo "::1 localhost ip6-localhost ip6-loopback" >>/etc/hosts
fi
if ! grep -qE "(^|[[:space:]])${UUID}($|[[:space:]])" /etc/hosts; then
  echo "127.0.0.1 ${UUID}" >>/etc/hosts
fi

echo -n "${UUID}" >/etc/hostname
