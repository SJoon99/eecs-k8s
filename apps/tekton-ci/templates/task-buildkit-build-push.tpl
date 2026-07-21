{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: {{ required "ci.names.buildPushTask is required" .Values.ci.names.buildPushTask | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Build a Child image with rootless BuildKit and push it to a bounded OCI registry prefix.
  params:
    - name: child-name
      type: string
    - name: source-revision
      type: string
    - name: build-context
      type: string
    - name: dockerfile
      type: string
    - name: image-name
      type: string
  workspaces:
    - name: source
      description: Checked-out Child source tree.
  results:
    - name: image-url
      description: OCI image repository without tag or digest.
    - name: image-tag
      description: Immutable source-SHA tag pushed by this run.
    - name: image-digest
      description: OCI digest returned by BuildKit.
  stepTemplate:
    env:
      - name: BUILDKITD_FLAGS
        value: --oci-worker-no-process-sandbox
      - name: DOCKER_CONFIG
        value: /home/user/.docker
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
      - name: registry-credentials
        mountPath: /home/user/.docker
        readOnly: true
  volumes:
    - name: registry-credentials
      secret:
        secretName: {{ required "ci.registry.credentialsSecretName is required" .Values.ci.registry.credentialsSecretName | quote }}
        items:
          - key: .dockerconfigjson
            path: config.json
  steps:
    - name: build-and-push
      image: {{ required "ci.images.buildkit is required" .Values.ci.images.buildkit | quote }}
      env:
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: SOURCE_REVISION
          value: $(params.source-revision)
        - name: BUILD_CONTEXT
          value: $(params.build-context)
        - name: DOCKERFILE
          value: $(params.dockerfile)
        - name: IMAGE_NAME
          value: $(params.image-name)
        - name: SOURCE_PATH
          value: $(workspaces.source.path)
        - name: REGISTRY_HOST
          value: {{ required "ci.registry.host is required when ci.enabled=true" .Values.ci.registry.host | quote }}
        - name: REGISTRY_REPOSITORY_PREFIX
          value: {{ required "ci.registry.repositoryPrefix is required when ci.enabled=true" .Values.ci.registry.repositoryPrefix | quote }}
        - name: REGISTRY_INSECURE
          value: {{ .Values.ci.registry.insecure | quote }}
      script: |
        #!/bin/sh
        set -eu

        context="${SOURCE_PATH}/${BUILD_CONTEXT}"
        [ -d "$context" ] || {
          printf 'build context not found: %s\n' "$context" >&2
          exit 1
        }
        [ -f "$context/$DOCKERFILE" ] || {
          printf 'Dockerfile not found: %s\n' "$context/$DOCKERFILE" >&2
          exit 1
        }

        image_url="${REGISTRY_HOST}/${REGISTRY_REPOSITORY_PREFIX}/${CHILD_NAME}/${IMAGE_NAME}"
        image_tag="sha-${SOURCE_REVISION}"
        output="type=image,name=${image_url}:${image_tag},push=true"
        if [ "$REGISTRY_INSECURE" = true ]; then
          output="${output},registry.insecure=true"
        fi

        buildctl-daemonless.sh build \
          --frontend dockerfile.v0 \
          --local context="$context" \
          --local dockerfile="$context" \
          --opt filename="$DOCKERFILE" \
          --output "$output" \
          --metadata-file /tmp/build-metadata.json

        image_digest="$(sed -n 's/.*"containerimage.digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/build-metadata.json | head -n 1)"
        case "$image_digest" in
          sha256:*) ;;
          *) printf 'BuildKit did not return an OCI digest\n' >&2; exit 1 ;;
        esac

        printf '%s' "$image_url" >"$(results.image-url.path)"
        printf '%s' "$image_tag" >"$(results.image-tag.path)"
        printf '%s' "$image_digest" >"$(results.image-digest.path)"
{{- end }}
