#!/usr/bin/env bash

set -euo pipefail

EECS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOWER_DIR="$(dirname "$EECS_DIR")/tower-k8s"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

require() {
  command -v "$1" >/dev/null || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

for command in awk grep helm; do
  require "$command"
done

helm template openark-kiss "$EECS_DIR/apps/openark-kiss" \
  --namespace kiss \
  -f "$EECS_DIR/values.yaml" \
  -f "$TOWER_DIR/values.yaml" \
  >"$TMP_DIR/openark-kiss.yaml"

helm template openark-kiss-pxe-edge "$EECS_DIR/apps/openark-kiss-pxe-edge" \
  --namespace tower-pxe-edge \
  -f "$EECS_DIR/values.yaml" \
  -f "$TOWER_DIR/values.yaml" \
  -f "$TOWER_DIR/patches/openark-kiss-pxe-edge/values.yaml" \
  >"$TMP_DIR/openark-kiss-pxe-edge.yaml"

grep -F 'set dns 10.64.0.3' "$TMP_DIR/openark-kiss.yaml" >/dev/null
grep -F 'iseq ${arch} arm64 && set dns 1.1.1.1 ||' \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null
grep -F 'iseq ${arch} amd64 && set repo ${assets}/assets/ubuntu-${os_ver} ||' \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null
grep -F 'iseq ${arch} arm64 && set repo ${assets}/assets/ubuntu-${os_ver}-arm64 ||' \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null
grep -F 'iseq ${arch} arm64 && set image_url ${repo}/ubuntu-${os_ver}${os_rev}-live-server-arm64+largemem.iso ||' \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null

grep -F "echo 'sbsa_gwdt' >/etc/modules-load.d/sbsa_gwdt.conf" \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null
if grep -F 'modprobe sbsa_gwdt' "$TMP_DIR/openark-kiss.yaml" >/dev/null; then
  echo 'DGX Spark watchdog must be deferred until the installed system boots' >&2
  exit 1
fi
grep -F 'if systemd-detect-virt --quiet --chroot; then' \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null

grep -F 'location /assets/ubuntu-24.04-arm64' "$TMP_DIR/openark-kiss.yaml" >/dev/null
grep -F 'proxy_pass http://cdimage.ubuntu.com/ubuntu/releases/24.04/release;' \
  "$TMP_DIR/openark-kiss.yaml" >/dev/null

dns_service="$(awk '
  function flush_document() {
    if (source == "openark-kiss/templates/deployment-dns.yaml" && kind == "Service") {
      printf "%s", document
    }
  }

  /^---$/ {
    flush_document()
    document = ""
    source = ""
    kind = ""
    next
  }

  {
    document = document $0 ORS
  }

  /^# Source: / {
    source = substr($0, 11)
  }

  /^kind: / {
    kind = substr($0, 7)
  }

  END {
    flush_document()
  }
' "$TMP_DIR/openark-kiss.yaml")"
grep -A3 '^  selector:$' <<<"$dns_service" |
  grep -F 'app.kubernetes.io/component: dns' >/dev/null

grep -F -- '--dhcp-option=6,$(DHCP_RANGE_IPV4_NAMESERVER_1),$(DHCP_RANGE_IPV4_NAMESERVER_FALLBACK_1),$(DHCP_RANGE_IPV4_NAMESERVER_FALLBACK_2)' \
  "$TMP_DIR/openark-kiss-pxe-edge.yaml" >/dev/null

echo "OpenARK KISS ARM64 PXE regression: PASS"
