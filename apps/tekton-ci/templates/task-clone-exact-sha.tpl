{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{ required "ci.names.cloneTask is required" .Values.ci.names.cloneTask | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Clone an enrolled public Child repository at one exact commit SHA.
  params:
    - name: repo-url
      type: string
    - name: source-revision
      type: string
  workspaces:
    - name: source
      description: Empty workspace populated with the checked-out source tree.
  results:
    - name: checked-out-revision
      description: Commit SHA verified after checkout.
  steps:
    - name: clone
      image: {{ required "ci.images.git is required" .Values.ci.images.git | quote }}
      env:
        - name: REPO_URL
          value: $(params.repo-url)
        - name: SOURCE_REVISION
          value: $(params.source-revision)
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

        rm -rf "${SOURCE_PATH:?}"/* "${SOURCE_PATH}"/.[!.]* "${SOURCE_PATH}"/..?* 2>/dev/null || true
        git init "$SOURCE_PATH"
        git -C "$SOURCE_PATH" remote add origin "$REPO_URL"
        git -C "$SOURCE_PATH" fetch --depth=1 origin "$SOURCE_REVISION"
        git -C "$SOURCE_PATH" checkout --detach FETCH_HEAD

        actual_revision="$(git -C "$SOURCE_PATH" rev-parse HEAD)"
        [ "$actual_revision" = "$SOURCE_REVISION" ] || {
          printf 'checkout mismatch: expected %s, got %s\n' "$SOURCE_REVISION" "$actual_revision" >&2
          exit 1
        }
        printf '%s' "$actual_revision" >"$(results.checked-out-revision.path)"
{{- end }}
