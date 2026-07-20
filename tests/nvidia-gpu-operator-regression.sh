#!/usr/bin/env bash

set -euo pipefail

EECS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

require() {
  command -v "$1" >/dev/null || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

for command in grep helm yq; do
  require "$command"
done

cat >"$TMP_DIR/cluster-values.yaml" <<'EOF'
cluster:
  name: gpu-test
  group: ops
features:
  - nvidia.com/gpu
  - org.ulagbulag.io/cni
  - org.ulagbulag.io/csi
  - org.ulagbulag.io/distributed-storage-cluster/ceph
repo:
  baseUrl: https://github.com
  owner: SJoon99
  name: eecs-k8s
  revision: main
tower:
  cluster: tower
  controlPlane: false
  group: ops
EOF

helm template smartx "$EECS_DIR" \
  -f "$TMP_DIR/cluster-values.yaml" \
  >"$TMP_DIR/applications.yaml"

yq 'select(.kind == "Application" and
  .metadata.name == "gpu-test-nvidia-gpu-operator")' \
  "$TMP_DIR/applications.yaml" >"$TMP_DIR/gpu-application.yaml"
yq 'select(.kind == "Application" and
  .metadata.name == "gpu-test-rook-ceph-operator")' \
  "$TMP_DIR/applications.yaml" >"$TMP_DIR/rook-application.yaml"

yq -e '.spec.sources[0].targetRevision == "v26.3.3" and
  .spec.sources[0].helm.valueFiles[1] ==
    "$cluster/patches/nvidia-gpu-operator/values.yaml" and
  .spec.sources[-1].ref == "cluster"' \
  "$TMP_DIR/gpu-application.yaml" >/dev/null

yq -e '.driver.kernelModuleType == "open" and
  (.driver | has("useOpenKernelModules") | not) and
  (.toolkit | has("toolkit") | not) and
  (.operator | has("defaultRuntime") | not)' \
  "$EECS_DIR/apps/nvidia-gpu-operator/values.yaml" >/dev/null
if grep -q 'defaultRuntime' \
  "$EECS_DIR/apps/nvidia-gpu-operator/patches.yaml"; then
  echo "GPU Operator patches contain an unsupported defaultRuntime value" >&2
  exit 1
fi

yq -e '.spec.sources[0].helm.valuesObject.csi.pluginTolerations[] |
  select(.key == "nvidia.com/gpu" and .effect == "NoSchedule")' \
  "$TMP_DIR/rook-application.yaml" >/dev/null
yq -e '.spec.sources[0].helm.valuesObject.discover.tolerations[] |
  select(.key == "nvidia.com/gpu" and .effect == "NoSchedule")' \
  "$TMP_DIR/rook-application.yaml" >/dev/null

yq '.spec.sources[0].helm.valuesObject' \
  "$TMP_DIR/gpu-application.yaml" >"$TMP_DIR/common-values.yaml"
helm template nvidia-gpu-operator gpu-operator \
  --repo https://helm.ngc.nvidia.com/nvidia \
  --version v26.3.3 \
  --namespace gpu-nvidia \
  -f "$EECS_DIR/apps/nvidia-gpu-operator/values.yaml" \
  -f "$TMP_DIR/common-values.yaml" \
  >"$TMP_DIR/gpu-operator.yaml"

yq -e 'select(.kind == "ClusterPolicy") |
  .spec.driver.kernelModuleType == "open" and
  .spec.toolkit.version == "v1.19.1" and
  .spec.devicePlugin.enabled == true' \
  "$TMP_DIR/gpu-operator.yaml" >/dev/null

echo "NVIDIA GPU Operator regression: PASS"
