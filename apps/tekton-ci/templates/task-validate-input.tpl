{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{ required "ci.names.validateInputTask is required" .Values.ci.names.validateInputTask | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Validate the bounded input contract for an enrolled Child build.
  params:
    - name: child-name
      type: string
    - name: repo-url
      type: string
    - name: source-revision
      type: string
    - name: chart-path
      type: string
    - name: build-context
      type: string
    - name: dockerfile
      type: string
    - name: image-name
      type: string
  steps:
    - name: validate
      image: {{ required "ci.images.shell is required" .Values.ci.images.shell | quote }}
      computeResources: {}
      env:
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: REPO_URL
          value: $(params.repo-url)
        - name: SOURCE_REVISION
          value: $(params.source-revision)
        - name: CHART_PATH
          value: $(params.chart-path)
        - name: BUILD_CONTEXT
          value: $(params.build-context)
        - name: DOCKERFILE
          value: $(params.dockerfile)
        - name: IMAGE_NAME
          value: $(params.image-name)
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

        fail() {
          printf 'invalid CI input: %s\n' "$1" >&2
          exit 1
        }

        validate_dns_label() {
          value="$1"
          field="$2"
          [ "${#value}" -le 63 ] || fail "$field exceeds 63 characters"
          case "$value" in
            ''|*[!a-z0-9-]*|-*|*-) fail "$field must be a lowercase DNS label" ;;
          esac
        }

        validate_relative_path() {
          value="$1"
          field="$2"
          [ -n "$value" ] || fail "$field is empty"
          case "$value" in
            /*) fail "$field must be relative" ;;
          esac
          case "/$value/" in
            *'/../'*|*'//'*) fail "$field contains an unsafe path segment" ;;
          esac
        }

        validate_dns_label "$CHILD_NAME" child-name
        validate_dns_label "$IMAGE_NAME" image-name

        case "$REPO_URL" in
          https://github.com/*/*.git) ;;
          *) fail 'repo-url must be an HTTPS GitHub .git URL' ;;
        esac
        case "$REPO_URL" in
          *[!A-Za-z0-9._:/-]*) fail 'repo-url contains unsupported characters' ;;
        esac

        [ "${#SOURCE_REVISION}" -eq 40 ] || fail 'source-revision must be a 40-character SHA'
        case "$SOURCE_REVISION" in
          *[!0-9a-f]*) fail 'source-revision must be a lowercase hexadecimal SHA' ;;
        esac

        validate_relative_path "$CHART_PATH" chart-path
        validate_relative_path "$BUILD_CONTEXT" build-context
        validate_relative_path "$DOCKERFILE" dockerfile
{{- end }}
