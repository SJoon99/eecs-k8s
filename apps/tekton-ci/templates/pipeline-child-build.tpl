{{- if .Values.ci.enabled }}
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: {{ required "ci.names.pipeline is required" .Values.ci.names.pipeline | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Validate, clone, render, build, and publish one enrolled Child revision.
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
      default: .
    - name: dockerfile
      type: string
      default: Dockerfile
    - name: image-name
      type: string
  workspaces:
    - name: source
      description: PipelineRun-provided source workspace.
  results:
    - name: source-revision
      description: Exact source revision verified by the clone Task.
      value: $(tasks.clone.results.checked-out-revision)
    - name: image-url
      description: OCI image repository without tag or digest.
      value: $(tasks.build-push.results.image-url)
    - name: image-tag
      description: Immutable source-SHA image tag.
      value: $(tasks.build-push.results.image-tag)
    - name: image-digest
      description: OCI image digest for Federation promotion.
      value: $(tasks.build-push.results.image-digest)
  tasks:
    - name: validate-input
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.validateInputTask | quote }}
      params:
        - name: child-name
          value: $(params.child-name)
        - name: repo-url
          value: $(params.repo-url)
        - name: source-revision
          value: $(params.source-revision)
        - name: chart-path
          value: $(params.chart-path)
        - name: build-context
          value: $(params.build-context)
        - name: dockerfile
          value: $(params.dockerfile)
        - name: image-name
          value: $(params.image-name)
    - name: clone
      runAfter:
        - validate-input
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.cloneTask | quote }}
      params:
        - name: repo-url
          value: $(params.repo-url)
        - name: source-revision
          value: $(params.source-revision)
      workspaces:
        - name: source
          workspace: source
    - name: helm-validate
      runAfter:
        - clone
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.helmValidateTask | quote }}
      params:
        - name: child-name
          value: $(params.child-name)
        - name: chart-path
          value: $(params.chart-path)
      workspaces:
        - name: source
          workspace: source
    - name: build-push
      runAfter:
        - helm-validate
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.buildPushTask | quote }}
      params:
        - name: child-name
          value: $(params.child-name)
        - name: source-revision
          value: $(params.source-revision)
        - name: build-context
          value: $(params.build-context)
        - name: dockerfile
          value: $(params.dockerfile)
        - name: image-name
          value: $(params.image-name)
      workspaces:
        - name: source
          workspace: source
{{- end }}
