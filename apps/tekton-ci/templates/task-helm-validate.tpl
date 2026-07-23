{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{ required "ci.names.helmValidateTask is required" .Values.ci.names.helmValidateTask | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Lint, render, and contract-check the Child-owned workload and Karmada policy chart.
  params:
    - name: child-name
      type: string
    - name: chart-path
      type: string
    - name: allowed-kinds
      type: string
      default: ""
      description: >-
        Comma-separated cluster-scoped kinds this Child is permitted to render.
        Mirrors requiredKinds in the Federation release descriptor. Empty means
        the Child renders namespaced resources only.
  workspaces:
    - name: source
      description: Checked-out Child source tree.
  volumes:
    # Steps are separate containers, so /tmp is not shared. The rendered
    # manifest has to live on a volume for the contract check to read it.
    - name: state
      emptyDir: {}
  stepTemplate:
    volumeMounts:
      - name: state
        mountPath: /workspace-state
    securityContext:
      runAsNonRoot: true
      runAsUser: 65532
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      seccompProfile:
        type: RuntimeDefault
  steps:
    - name: lint-and-render
      image: {{ required "ci.images.helm is required" .Values.ci.images.helm | quote }}
      computeResources: {}
      env:
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: CHART_PATH
          value: $(params.chart-path)
        - name: SOURCE_PATH
          value: $(workspaces.source.path)
      script: |
        #!/bin/sh
        set -eu

        chart="${SOURCE_PATH}/${CHART_PATH}"
        [ -f "$chart/Chart.yaml" ] || {
          printf 'Chart.yaml not found under %s\n' "$chart" >&2
          exit 1
        }
        helm lint "$chart"
        # Render into a probe namespace so a chart that hardcodes some other
        # namespace is visible as a mismatch rather than silently accepted.
        helm template "$CHILD_NAME" "$chart" --namespace "$CHILD_NAME" \
          >/workspace-state/rendered.yaml
        [ -s /workspace-state/rendered.yaml ] || {
          printf 'Helm rendered no resources for %s\n' "$chart" >&2
          exit 1
        }

    - name: validate-contract
      image: {{ required "promotion.images.yq is required" .Values.promotion.images.yq | quote }}
      computeResources: {}
      env:
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: ALLOWED_KINDS
          value: $(params.allowed-kinds)
      script: |
        #!/bin/sh
        set -eu

        cat >/workspace-state/validate-render.sh <<'VALIDATOR'
        {{- .Files.Get "files/validate-render.sh" | nindent 8 }}
        VALIDATOR

        set -- --profile=child --namespace "$CHILD_NAME"
        [ -z "$ALLOWED_KINDS" ] || set -- "$@" --allow-kinds="$ALLOWED_KINDS"
        sh /workspace-state/validate-render.sh "$@" /workspace-state/rendered.yaml
{{- end }}
