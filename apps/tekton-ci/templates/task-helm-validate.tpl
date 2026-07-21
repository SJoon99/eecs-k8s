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
  description: Lint and render the Child-owned workload and Karmada policy chart.
  params:
    - name: child-name
      type: string
    - name: chart-path
      type: string
  workspaces:
    - name: source
      description: Checked-out Child source tree.
  steps:
    - name: lint-and-render
      image: {{ required "ci.images.helm is required" .Values.ci.images.helm | quote }}
      env:
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: CHART_PATH
          value: $(params.chart-path)
        - name: SOURCE_PATH
          value: $(workspaces.source.path)
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        seccompProfile:
          type: RuntimeDefault
      script: |
        #!/bin/sh
        set -eu

        chart="${SOURCE_PATH}/${CHART_PATH}"
        [ -f "$chart/Chart.yaml" ] || {
          printf 'Chart.yaml not found under %s\n' "$chart" >&2
          exit 1
        }
        helm lint "$chart"
        helm template "$CHILD_NAME" "$chart" >/tmp/rendered.yaml
        [ -s /tmp/rendered.yaml ] || {
          printf 'Helm rendered no resources for %s\n' "$chart" >&2
          exit 1
        }
{{- end }}
