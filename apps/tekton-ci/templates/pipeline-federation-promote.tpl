{{- if and .Values.ci.enabled .Values.promotion.enabled }}
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: {{ required "promotion.names.pipeline is required" .Values.promotion.names.pipeline | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  description: Turn a successful Child build payload into a human-reviewed Federation pull request.
  params:
    - name: payload
      type: string
  results:
    - name: branch
      description: Promotion branch pushed to the Federation repository.
      value: $(tasks.promote.results.branch)
    - name: changed
      description: Whether Federation files changed.
      value: $(tasks.promote.results.changed)
    - name: pull-request-url
      description: Human-reviewed Federation pull request URL.
      value: $(tasks.promote.results.pull-request-url)
  tasks:
    - name: promote
      taskRef:
        kind: Task
        name: {{ .Values.promotion.names.task | quote }}
      params:
        - name: payload
          value: $(params.payload)
{{- end }}
