{{- if .Values.workspace.persistentVolumeClaim.enabled }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ required "workspace.persistentVolumeClaim.name is required" .Values.workspace.persistentVolumeClaim.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  accessModes:
{{- toYaml .Values.workspace.persistentVolumeClaim.accessModes | nindent 4 }}
{{- with .Values.workspace.persistentVolumeClaim.storageClassName }}
  storageClassName: {{ . | quote }}
{{- end }}
  resources:
    requests:
      storage: {{ .Values.workspace.persistentVolumeClaim.size | quote }}
{{- end }}
