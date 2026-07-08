{{/*
Expand the name of the chart.
*/}}
{{- define "helm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "helm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "helm.labels" -}}
helm.sh/chart: {{ include "helm.chart" . }}
{{ include "helm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "helm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "helm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service Accounts
*/}}
{{- define "helm.serviceAccountAnsiblePlaybookName" -}}
{{- printf "ansible-playbook" }}
{{- end }}
{{- define "helm.serviceAccountSystemName" -}}
{{- printf "kiss-system" }}
{{- end }}


{{/*
Cluster Domain Name
*/}}
{{- define "helm.clusterDomainName" -}}
{{- .Values.cluster.domainName | default ( printf "ops.%s" .Values.cluster.domainBase ) }}
{{- end }}

{{/*
PXE node installer network body.

PXE-booted nodes must keep the discovery DHCP lease during Ubuntu
autoinstall. The seed control-plane may use a site-specific static address, but
that static seed identity must not leak into worker/control-plane nodes that are
being installed from KISS assets.
*/}}
{{- define "helm.pxeNetworkBody" -}}
{{- $root := .root -}}
{{- $renderer := .renderer | default "NetworkManager" -}}
{{- $pxe := $root.Values.network.pxe | default dict -}}
{{- $match := $pxe.match | default dict -}}
{{- $matchName := $match.name | default "en*" -}}
{{- $mtu := $root.Values.network.interface.mtu | default 1500 -}}
version: 2
renderer: {{ $renderer }}
ethernets:
  alleths:
    match:
      name: {{ $matchName | quote }}
    mtu: {{ $mtu }}
    dhcp4: true
    optional: true
{{- end }}

{{/*
Seed installer network body.

The seed control-plane can be installed in either DHCP mode or static mode.
Static mode is intentionally driven by the site preset because the physical
management NIC and final IP are site/hardware facts, not framework defaults.
*/}}
{{- define "helm.seedNetworkBody" -}}
{{- $root := .root -}}
{{- $renderer := .renderer | default "networkd" -}}
{{- $seed := $root.Values.bootstrapper.network.seed | default dict -}}
{{- $mode := $seed.mode | default "dhcp" -}}
{{- $match := $seed.match | default dict -}}
{{- $static := $seed.static | default dict -}}
{{- $matchName := $match.name | default "en*" -}}
{{- $matchMac := $match.macaddress | default "" -}}
{{- $setName := $seed.setName | default "" -}}
{{- $mtu := $root.Values.network.interface.mtu | default 1500 -}}
{{- $address := "" -}}
{{- $prefix := "" -}}
{{- $gateway := "" -}}
{{- $nameservers := list -}}
{{- if or ( eq $mode "static" ) ( eq $mode "auto-static" ) -}}
{{- $address = required "bootstrapper.network.seed.static.address is required when seed mode is static" $static.address -}}
{{- $prefix = required "bootstrapper.network.seed.static.prefix is required when seed mode is static" $static.prefix -}}
{{- $gateway = required "bootstrapper.network.seed.static.gateway is required when seed mode is static" $static.gateway -}}
{{- $nameservers = $static.nameservers | default ( list $root.Values.network.nameservers.ns1 $root.Values.network.nameservers.ns2 ) -}}
{{- end -}}
version: 2
renderer: {{ $renderer }}
ethernets:
  seed:
    match:
{{- if $matchMac }}
      macaddress: {{ $matchMac | lower | quote }}
{{- else }}
      name: {{ $matchName | quote }}
{{- end }}
{{- if $setName }}
    set-name: {{ $setName | quote }}
{{- end }}
    mtu: {{ $mtu }}
{{ if eq $mode "static" }}
    dhcp4: false
    addresses:
      - {{ printf "%s/%v" $address $prefix | quote }}
    routes:
      - to: default
        via: {{ $gateway | quote }}
    nameservers:
      addresses:
{{- range $nameserver := $nameservers }}
        - {{ $nameserver | quote }}
{{- end }}
{{ else if or ( eq $mode "dhcp" ) ( eq $mode "auto-static" ) }}
    dhcp4: true
    optional: true
{{ else }}
{{- fail ( printf "Unsupported bootstrapper.network.seed.mode: %s" $mode ) }}
{{- end }}
{{- end }}

{{/*
Seed auto-static NIC selection script.

This is used only by standalone seed installs when the operator knows the final
seed IP but does not know the Linux interface name in advance. The selector
chooses the fastest carrier-up physical NIC that can actually reach the target
network, preventing the earlier failure mode where an otherwise-fast NIC was on
the wrong VLAN.
*/}}
{{- define "helm.seedAutoStaticScript" -}}
{{- $root := .root -}}
{{- $seed := $root.Values.bootstrapper.network.seed | default dict -}}
{{- $match := $seed.match | default dict -}}
{{- $auto := $seed.auto | default dict -}}
{{- $static := $seed.static | default dict -}}
{{- $matchName := $match.name | default "en*" -}}
{{- $mtu := $root.Values.network.interface.mtu | default 1500 -}}
{{- $address := required "bootstrapper.network.seed.static.address is required when seed mode is auto-static" $static.address -}}
{{- $prefix := required "bootstrapper.network.seed.static.prefix is required when seed mode is auto-static" $static.prefix -}}
{{- $gateway := required "bootstrapper.network.seed.static.gateway is required when seed mode is auto-static" $static.gateway -}}
{{- $nameservers := $static.nameservers | default ( list $root.Values.network.nameservers.ns1 $root.Values.network.nameservers.ns2 ) -}}
{{- $probeUrls := $auto.probeUrls | default ( list "http://mirror.kakao.com/ubuntu/" ) -}}
{{- $timeoutSeconds := $auto.timeoutSeconds | default 90 -}}
cat >/tmp/kumho-seed-auto-static.sh <<'KUMHO_SEED_AUTO_STATIC'
#!/usr/bin/env bash
set -euo pipefail

renderer="${1:-networkd}"
match_name={{ $matchName | quote }}
address={{ $address | quote }}
prefix={{ $prefix | quote }}
gateway={{ $gateway | quote }}
mtu={{ $mtu | quote }}
timeout_seconds={{ $timeoutSeconds | quote }}
nameservers=(
{{- range $nameserver := $nameservers }}
  {{ $nameserver | quote }}
{{- end }}
)
probe_urls=(
{{- range $url := $probeUrls }}
  {{ $url | quote }}
{{- end }}
)
log=/run/kumho-seed-auto-static.log
selected_file=/run/kumho-seed-interface

mkdir -p /run
exec > >(tee -a "$log") 2>&1

echo "[kumho] auto-static seed network: renderer=${renderer} address=${address}/${prefix} gateway=${gateway} match=${match_name}"

is_candidate() {
  local dev="$1"
  case "$dev" in
    lo|docker*|veth*|cni*|flannel*|br-*|virbr*|bond*|dummy*|tun*|tap*) return 1 ;;
  esac
  case "$dev" in
    $match_name) ;;
    *) return 1 ;;
  esac
  [ -d "/sys/class/net/${dev}/device" ] || return 1
}

speed_of() {
  local dev="$1" speed
  speed="$(cat "/sys/class/net/${dev}/speed" 2>/dev/null || true)"
  case "$speed" in
    ''|*[!0-9]* ) echo 0 ;;
    * ) echo "$speed" ;;
  esac
}

carrier_of() {
  cat "/sys/class/net/$1/carrier" 2>/dev/null || echo 0
}

candidate_lines() {
  local dev speed carrier
  for path in /sys/class/net/*; do
    dev="${path##*/}"
    is_candidate "$dev" || continue
    ip link set dev "$dev" up || true
  done

  sleep 2

  for path in /sys/class/net/*; do
    dev="${path##*/}"
    is_candidate "$dev" || continue
    carrier="$(carrier_of "$dev")"
    [ "$carrier" = '1' ] || continue
    speed="$(speed_of "$dev")"
    printf '%012d %s\n' "$speed" "$dev"
  done | sort -r -n -k1,1 -k2,2
}

write_netplan() {
  local dev="$1" ns
  cat >/etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  renderer: ${renderer}
  ethernets:
    seed:
      match:
        name: "${dev}"
      mtu: ${mtu}
      dhcp4: false
      addresses:
        - "${address}/${prefix}"
      routes:
        - to: default
          via: "${gateway}"
      nameservers:
        addresses:
EOF
  for ns in "${nameservers[@]}"; do
    printf '          - "%s"\n' "$ns" >>/etc/netplan/50-cloud-init.yaml
  done
}

clear_seed_addresses() {
  local path dev
  for path in /sys/class/net/*; do
    dev="${path##*/}"
    is_candidate "$dev" || continue
    ip -4 addr flush dev "$dev" scope global || true
  done
  ip route del default 2>/dev/null || true
}

enforce_runtime_route() {
  local dev="$1"
  ip link set dev "$dev" up mtu "$mtu" || true
  ip -4 addr flush dev "$dev" scope global || true
  ip addr add "${address}/${prefix}" dev "$dev" 2>/dev/null \
    || ip addr replace "${address}/${prefix}" dev "$dev"
  ip route replace default via "$gateway" dev "$dev"
}

write_autoinstall_network() {
  local dev="$1" path
  path=/autoinstall.yaml
  if [ ! -f "$path" ]; then
    echo "[kumho] ${path} not found; keeping runtime netplan only"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1 && python3 - "$path" "$renderer" "$dev" "$mtu" "$address" "$prefix" "$gateway" "${nameservers[@]}" <<'PY'
import sys
from pathlib import Path

import yaml

path, renderer, dev, mtu, address, prefix, gateway, *nameservers = sys.argv[1:]
p = Path(path)
data = yaml.safe_load(p.read_text()) or {}
# Depending on the Subiquity phase, /autoinstall.yaml can be either:
#   1. the full NoCloud document: {version: 1, autoinstall: {...}}
#   2. the autoinstall body itself: {version: 1, user-data: {...}, ...}
# Preserve the existing body in both cases; otherwise the seed network patch
# can accidentally drop user-data and make Subiquity stop with
# "neither identity nor user-data provided".
if isinstance(data.get("autoinstall"), dict):
    autoinstall = data["autoinstall"]
else:
    autoinstall = data
autoinstall["network"] = {
    "version": 2,
    "renderer": renderer,
    "ethernets": {
        "seed": {
            "match": {"name": dev},
            "mtu": int(mtu),
            "dhcp4": False,
            "addresses": [f"{address}/{prefix}"],
            "routes": [{"to": "default", "via": gateway}],
            "nameservers": {"addresses": nameservers},
        }
    },
}
# Subiquity re-loads /autoinstall.yaml as an autoinstall datasource. In that
# mode it rejects any top-level key next to "autoinstall" (for example the
# original cloud-init "version" key), so rewrite the file with autoinstall as
# the only top-level key.
p.write_text("#cloud-config\n" + yaml.safe_dump({"autoinstall": autoinstall}, sort_keys=False))
print(f"[kumho] patched {path} network for {dev}")
PY
  then
    return 0
  fi

  echo "[kumho] python yaml patch unavailable/failed; trying text fallback for ${path}"
  local block tmp
  block="$(cat <<EOF
  network:
    version: 2
    renderer: ${renderer}
    ethernets:
      seed:
        match:
          name: "${dev}"
        mtu: ${mtu}
        dhcp4: false
        addresses:
          - "${address}/${prefix}"
        routes:
          - to: default
            via: "${gateway}"
        nameservers:
          addresses:
EOF
  for ns in "${nameservers[@]}"; do
    printf '            - "%s"\n' "$ns"
  done
)"
  tmp="${path}.kumho"
  if grep -q '^autoinstall:' "$path"; then
    awk -v block="$block" '
      BEGIN { in_ai = 0; skipping = 0; inserted = 0; print "#cloud-config" }
      /^#cloud-config/ { next }
      /^version:/ { next }
      /^autoinstall:/ { in_ai = 1; print; print block; inserted = 1; next }
      in_ai && /^  network:/ { skipping = 1; next }
      in_ai && skipping && /^  [A-Za-z0-9_-]+:/ { skipping = 0; print; next }
      in_ai && skipping { next }
      { print }
      END { if (!inserted) exit 42 }
    ' "$path" >"$tmp"
  else
    awk -v block="$block" '
      BEGIN { skipping = 0; print "#cloud-config"; print "autoinstall:"; print block }
      /^#cloud-config/ { next }
      /^network:/ { skipping = 1; next }
      skipping && /^[A-Za-z0-9_-]+:/ { skipping = 0 }
      skipping { next }
      { print "  " $0 }
    ' "$path" >"$tmp"
  fi
  mv "$tmp" "$path"
  echo "[kumho] patched ${path} network for ${dev} with text fallback"
}

probe_candidate() {
  local dev="$1" url

  clear_seed_addresses
  write_netplan "$dev"
  echo "[kumho] trying ${dev} speed=$(speed_of "$dev") carrier=$(carrier_of "$dev")"
  if ! netplan apply; then
    echo "[kumho] netplan apply failed on ${dev}"
    return 1
  fi
  enforce_runtime_route "$dev"
  sleep 3

  ip -4 addr show dev "$dev" || true
  ip -4 route || true

  # Route existence alone is not enough, but it is a cheap first sanity check.
  ip -4 route get "$gateway" >/dev/null 2>&1 || {
    echo "[kumho] gateway route check failed on ${dev}"
    return 1
  }

  # Prefer an actual HTTP probe because ICMP may be blocked on some gateways.
  if command -v curl >/dev/null 2>&1; then
    for url in "${probe_urls[@]}"; do
      [ -n "$url" ] || continue
      echo "[kumho] probing ${url} via ${dev}"
      if curl -fsSL --connect-timeout 5 --max-time 12 "$url" >/dev/null; then
        echo "$dev" >"$selected_file"
        write_autoinstall_network "$dev"
        echo "[kumho] selected ${dev} by URL probe"
        return 0
      fi
    done
  fi

  # Fallback for restricted networks where HTTP probing is not available.
  if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
    echo "$dev" >"$selected_file"
    write_autoinstall_network "$dev"
    echo "[kumho] selected ${dev} by gateway ping"
    return 0
  fi

  echo "[kumho] reachability probe failed on ${dev}"
  return 1
}

deadline=$((SECONDS + timeout_seconds))
while [ "$SECONDS" -lt "$deadline" ]; do
  mapfile -t candidates < <(candidate_lines)
  if [ "${#candidates[@]}" -gt 0 ]; then
    printf '[kumho] candidates:\n'
    printf '  %s\n' "${candidates[@]}"
    for line in "${candidates[@]}"; do
      dev="${line#* }"
      if probe_candidate "$dev"; then
        exit 0
      fi
    done
  else
    echo "[kumho] waiting for carrier-up NICs matching ${match_name}"
  fi
  sleep 3
done

echo "[kumho] no reachable seed NIC found" >&2
exit 1
KUMHO_SEED_AUTO_STATIC
chmod 755 /tmp/kumho-seed-auto-static.sh
{{- end }}
