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
      default: ""
      description: >-
        Optional JSON array of enrolled image build targets. Empty derives the
        set from images/<name>/Dockerfile in the checked-out Child source.
    - name: allowed-kinds
      type: string
      default: ""
      description: >-
        Comma-separated cluster-scoped kinds this Child is permitted to render.
        Mirrors requiredKinds in the Federation release descriptor.
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
    - name: derive-targets
      runAfter:
        - clone
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.deriveTargetsTask | quote }}
      params:
        - name: build-targets
          value: $(params.build-targets)
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
        - name: allowed-kinds
          value: $(params.allowed-kinds)
      workspaces:
        - name: source
          workspace: source
    - name: build-push
      runAfter:
        - helm-validate
        - derive-targets
      taskRef:
        kind: Task
        name: {{ .Values.ci.names.buildPushTask | quote }}
      params:
        - name: child-name
          value: $(params.child-name)
        - name: source-revision
          value: $(params.source-revision)
        - name: chart-path
          value: $(params.chart-path)
        - name: build-targets
          value: $(tasks.derive-targets.results.build-targets)
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
{{- if .Values.promotion.enabled }}
    - name: promote
      runAfter:
        - create-promotion-payload
      taskRef:
        kind: Task
        name: {{ required "promotion.names.task is required" .Values.promotion.names.task | quote }}
      params:
        - name: payload
          value: $(tasks.create-promotion-payload.results.payload)
{{- end }}
{{- end }}
