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
  description: Validate, clone, render, and publish all enrolled images for one Child revision.
  params:
    - name: child-name
      type: string
    - name: repo-url
      type: string
    - name: source-revision
      type: string
    - name: chart-path
      type: string
    - name: build-targets
      type: string
      description: JSON array of enrolled image build targets.
  workspaces:
    - name: source
      description: PipelineRun-provided source workspace.
  results:
    - name: source-revision
      description: Exact source revision verified by the clone Task.
      value: $(tasks.clone.results.checked-out-revision)
    - name: images
      description: JSON map of all immutable image identities.
      value: $(tasks.build-push.results.images)
    - name: promotion-payload
      description: Versioned JSON payload consumed by the Federation promotion Pipeline.
      value: $(tasks.create-promotion-payload.results.payload)
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
        - name: build-targets
          value: $(params.build-targets)
      workspaces:
        - name: source
          workspace: source
    - name: create-promotion-payload
      runAfter:
        - build-push
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.promotionPayloadTask | quote }}
      params:
        - name: child-name
          value: $(params.child-name)
        - name: source-revision
          value: $(tasks.clone.results.checked-out-revision)
        - name: images
          value: $(tasks.build-push.results.images)
        - name: pipeline-run
          value: $(context.pipelineRun.name)
{{- end }}
