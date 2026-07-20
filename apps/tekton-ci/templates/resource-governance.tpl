{{- if .Values.resourceQuota.enabled }}
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {{ required "resourceQuota.name is required" .Values.resourceQuota.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  hard:
{{- toYaml .Values.resourceQuota.hard | nindent 4 }}
{{- end }}
{{- if .Values.limitRange.enabled }}
---
apiVersion: v1
kind: LimitRange
metadata:
  name: {{ required "limitRange.name is required" .Values.limitRange.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  limits:
    - type: Container
      default:
{{- toYaml .Values.limitRange.container.default | nindent 8 }}
      defaultRequest:
{{- toYaml .Values.limitRange.container.defaultRequest | nindent 8 }}
{{- end }}
