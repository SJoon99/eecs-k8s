{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{ required "ci.names.promotionPayloadTask is required" .Values.ci.names.promotionPayloadTask | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Create a bounded JSON payload for a separate Federation promotion Pipeline.
  params:
    - name: child-name
      type: string
    - name: source-revision
      type: string
    - name: images
      type: string
    - name: pipeline-run
      type: string
  results:
    - name: payload
      type: string
      description: Versioned promotion payload serialized as compact JSON.
  steps:
    - name: create
      image: {{ required "promotion.images.yq is required" .Values.promotion.images.yq | quote }}
      computeResources: {}
      env:
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: SOURCE_REVISION
          value: $(params.source-revision)
        - name: IMAGES
          value: $(params.images)
        - name: PIPELINE_RUN
          value: $(params.pipeline-run)
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

        [ "${#SOURCE_REVISION}" -eq 40 ] || {
          printf 'source revision must be a 40-character SHA\n' >&2
          exit 1
        }
        case "$SOURCE_REVISION" in
          *[!0-9a-f]*) printf 'source revision must be lowercase hexadecimal\n' >&2; exit 1 ;;
        esac
        printf '%s' "$IMAGES" >/tmp/images.json
        count="$(yq -r 'length' /tmp/images.json)"
        [ "$count" -gt 0 ] || { printf 'promotion requires at least one image\n' >&2; exit 1; }
        SOURCE_REVISION="$SOURCE_REVISION" yq -e '[.[] | (
          .sourceRevision == strenv(SOURCE_REVISION) and
          .immutableTag == ("sha-" + strenv(SOURCE_REVISION)) and
          (.tag | test("^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$")) and
          (.digest | test("^sha256:[0-9a-f]{64}$"))
        )] | all' /tmp/images.json >/dev/null
        CHILD_NAME="$CHILD_NAME" SOURCE_REVISION="$SOURCE_REVISION" PIPELINE_RUN="$PIPELINE_RUN" \
        yq -n -o=json -I=0 \
          '{"schemaVersion":"v1","childName":strenv(CHILD_NAME),"sourceRevision":strenv(SOURCE_REVISION),"pipelineRun":strenv(PIPELINE_RUN),"images":load("/tmp/images.json")}' \
          | tr -d '\n' >"$(results.payload.path)"
{{- end }}
