{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{ required "ci.names.deriveTargetsTask is required" .Values.ci.names.deriveTargetsTask | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Resolve the image build target set for one Child revision from its own repository layout.
  params:
    - name: build-targets
      type: string
      default: ""
      description: >-
        Optional operator-supplied JSON array of build targets. When non-empty it
        is validated and used verbatim (backward compatible). When empty the set
        is derived from images/<name>/Dockerfile in the checked-out source, so the
        Child repository is the single source of truth for its own image inventory.
  workspaces:
    - name: source
      description: Checked-out Child source tree.
  results:
    - name: build-targets
      type: string
      description: Resolved JSON array of name, valuesKey, context and dockerfile objects.
  volumes:
    - name: state
      emptyDir: {}
  steps:
    - name: derive
      image: {{ required "promotion.images.yq is required" .Values.promotion.images.yq | quote }}
      computeResources: {}
      env:
        - name: BUILD_TARGETS
          value: $(params.build-targets)
        - name: SOURCE_PATH
          value: $(workspaces.source.path)
      volumeMounts:
        - name: state
          mountPath: /workspace-state
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      script: |
        #!/bin/sh
        set -eu

        # Operator-supplied targets win, so an explicit PipelineRun keeps working.
        compact="$(printf '%s' "$BUILD_TARGETS" | tr -d '[:space:]')"
        if [ -n "$compact" ]; then
          printf '%s' "$BUILD_TARGETS" >/workspace-state/targets.json
          kind="$(yq -p=json '. | tag' /workspace-state/targets.json 2>/dev/null || printf '')"
          [ "$kind" = "!!seq" ] || { printf 'build-targets must be a JSON array\n' >&2; exit 1; }
          length="$(yq -p=json '. | length' /workspace-state/targets.json)"
          [ "$length" -gt 0 ] || { printf 'build-targets array is empty\n' >&2; exit 1; }
          yq -p=json -o=json -I=0 '.' /workspace-state/targets.json | tr -d '\n' >"$(results.build-targets.path)"
          exit 0
        fi

        # No explicit targets: derive from images/<name>/Dockerfile in the source.
        images_dir="${SOURCE_PATH}/images"
        : >/workspace-state/components
        if [ -d "$images_dir" ]; then
          find "$images_dir" -mindepth 2 -maxdepth 2 -type f -name Dockerfile \
            | LC_ALL=C sort >/workspace-state/dockerfiles
          while IFS= read -r dockerfile; do
            [ -n "$dockerfile" ] || continue
            component="$(basename "$(dirname "$dockerfile")")"
            printf '%s' "$component" | grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' || {
              printf 'image directory must be lowercase kebab-case: %s\n' "$component" >&2
              exit 1
            }
            printf '%s\n' "$component" >>/workspace-state/components
          done </workspace-state/dockerfiles
        fi
        [ -s /workspace-state/components ] || {
          printf 'no images/*/Dockerfile found and no explicit build-targets provided\n' >&2
          exit 1
        }
        [ "$(sort /workspace-state/components | uniq -d | wc -l)" -eq 0 ] || {
          printf 'duplicate image component\n' >&2
          exit 1
        }

        # Components are kebab-validated, so embedding them in JSON is safe. The
        # build context is always the repo root because a Child that keeps sources
        # in src/<name> and Dockerfiles in images/<name> needs the whole tree.
        {
          printf '['
          separator=''
          while IFS= read -r component; do
            printf '%s{"name":"%s","valuesKey":"%s","context":".","dockerfile":"images/%s/Dockerfile"}' \
              "$separator" "$component" "$component" "$component"
            separator=','
          done </workspace-state/components
          printf ']'
        } >/workspace-state/targets.json

        yq -p=json -o=json -I=0 '.' /workspace-state/targets.json | tr -d '\n' >"$(results.build-targets.path)"
{{- end }}
