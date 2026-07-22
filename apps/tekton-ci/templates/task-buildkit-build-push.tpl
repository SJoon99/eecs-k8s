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
  description: Build every enrolled image target for one Child revision and push them atomically as one result set.
  params:
    - name: child-name
      type: string
    - name: source-revision
      type: string
    - name: build-targets
      type: string
      description: JSON array of name, valuesKey, context and dockerfile objects.
  workspaces:
    - name: source
      description: Checked-out Child source tree.
  results:
    - name: images
      type: string
      description: Compact JSON map of all pushed image identities keyed by Helm values key.
  volumes:
    - name: state
      emptyDir: {}
    - name: registry-credentials
      secret:
        secretName: {{ required "ci.registry.credentialsSecretName is required" .Values.ci.registry.credentialsSecretName | quote }}
        items:
          - key: .dockerconfigjson
            path: config.json
  steps:
    - name: validate-targets
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
        printf '%s' "$BUILD_TARGETS" >/workspace-state/targets.json
        count="$(yq -r 'length' /workspace-state/targets.json)"
        [ "$count" -gt 0 ] || { printf 'at least one build target is required\n' >&2; exit 1; }
        yq -r '.[] | [.name, .valuesKey, .context, .dockerfile] | @tsv' \
          /workspace-state/targets.json >/workspace-state/targets.tsv
        : >/workspace-state/names
        : >/workspace-state/keys
        tab="$(printf '\t')"
        while IFS="$tab" read -r name values_key context dockerfile; do
          printf '%s' "$name" | grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' || { printf 'invalid image name: %s\n' "$name" >&2; exit 1; }
          printf '%s' "$values_key" | grep -Eq '^[A-Za-z][A-Za-z0-9]*$' || { printf 'invalid values key: %s\n' "$values_key" >&2; exit 1; }
          for path in "$context" "$dockerfile"; do
            case "$path" in ''|/*|*../*|*/..|*//*) printf 'unsafe build path: %s\n' "$path" >&2; exit 1;; esac
          done
          [ -d "$SOURCE_PATH/$context" ] || { printf 'build context not found: %s\n' "$context" >&2; exit 1; }
          [ -f "$SOURCE_PATH/$context/$dockerfile" ] || { printf 'Dockerfile not found: %s/%s\n' "$context" "$dockerfile" >&2; exit 1; }
          printf '%s\n' "$name" >>/workspace-state/names
          printf '%s\n' "$values_key" >>/workspace-state/keys
        done </workspace-state/targets.tsv
        [ "$(sort /workspace-state/names | uniq -d | wc -l)" -eq 0 ] || { printf 'duplicate image name\n' >&2; exit 1; }
        [ "$(sort /workspace-state/keys | uniq -d | wc -l)" -eq 0 ] || { printf 'duplicate values key\n' >&2; exit 1; }

    - name: build-and-push
      image: {{ required "ci.images.buildkit is required" .Values.ci.images.buildkit | quote }}
      computeResources: {}
      env:
        - name: BUILDKITD_FLAGS
          value: --oci-worker-no-process-sandbox
        - name: DOCKER_CONFIG
          value: /home/user/.docker
        - name: CHILD_NAME
          value: $(params.child-name)
        - name: SOURCE_REVISION
          value: $(params.source-revision)
        - name: SOURCE_PATH
          value: $(workspaces.source.path)
        - name: REGISTRY_HOST
          value: {{ required "ci.registry.host is required when ci.enabled=true" .Values.ci.registry.host | quote }}
        - name: REGISTRY_REPOSITORY_PREFIX
          value: {{ required "ci.registry.repositoryPrefix is required when ci.enabled=true" .Values.ci.registry.repositoryPrefix | quote }}
        - name: REGISTRY_INSECURE
          value: {{ .Values.ci.registry.insecure | quote }}
      volumeMounts:
        - name: state
          mountPath: /workspace-state
        - name: registry-credentials
          mountPath: /home/user/.docker
          readOnly: true
      securityContext:
        privileged: true
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: true
        seccompProfile:
          type: Unconfined
        appArmorProfile:
          type: Unconfined
      script: |
        #!/bin/sh
        set -eu
        : >/workspace-state/images.tsv
        tab="$(printf '\t')"
        while IFS="$tab" read -r image_name values_key build_context dockerfile; do
          context="${SOURCE_PATH}/${build_context}"
          image_url="${REGISTRY_HOST}/${REGISTRY_REPOSITORY_PREFIX}/${CHILD_NAME}/${image_name}"
          image_tag="sha-${SOURCE_REVISION}"
          output="type=image,name=${image_url}:${image_tag},push=true"
          [ "$REGISTRY_INSECURE" = true ] && output="${output},registry.insecure=true"
          metadata="/workspace-state/${image_name}-metadata.json"
          buildctl-daemonless.sh build \
            --frontend dockerfile.v0 \
            --local context="$context" \
            --local dockerfile="$context" \
            --opt filename="$dockerfile" \
            --output "$output" \
            --metadata-file "$metadata"
          digest="$(sed -n 's/.*"containerimage.digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata" | head -n 1)"
          case "$digest" in sha256:*) ;; *) printf 'BuildKit digest missing for %s\n' "$image_name" >&2; exit 1;; esac
          printf '%s\t%s\t%s\t%s\t%s\n' "$image_name" "$values_key" "$image_url" "$image_tag" "$digest" >>/workspace-state/images.tsv
        done </workspace-state/targets.tsv

    - name: emit-images
      image: {{ .Values.promotion.images.yq | quote }}
      computeResources: {}
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
        printf '{}\n' >/workspace-state/images.json
        tab="$(printf '\t')"
        while IFS="$tab" read -r name key repository tag digest; do
          KEY="$key" NAME="$name" REPOSITORY="$repository" TAG="$tag" DIGEST="$digest" SOURCE_REVISION="$(params.source-revision)" \
          yq -o=json -I=0 -i '.[strenv(KEY)] = {"name": strenv(NAME), "repository": strenv(REPOSITORY), "tag": strenv(TAG), "digest": strenv(DIGEST), "sourceRevision": strenv(SOURCE_REVISION)}' \
            /workspace-state/images.json
        done </workspace-state/images.tsv
        tr -d '\n' </workspace-state/images.json >"$(results.images.path)"
{{- end }}
