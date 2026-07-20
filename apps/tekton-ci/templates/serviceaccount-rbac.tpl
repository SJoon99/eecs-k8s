{{- if .Values.serviceAccount.create }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ required "serviceAccount.name is required" .Values.serviceAccount.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken }}
{{- end }}
{{- if .Values.rbac.create }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ required "rbac.name is required" .Values.rbac.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
{{- with .Values.rbac.rules }}
rules:
{{- toYaml . | nindent 2 }}
{{- else }}
rules: []
{{- end }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ required "rbac.name is required" .Values.rbac.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ .Values.rbac.name | quote }}
subjects:
  - kind: ServiceAccount
    name: {{ .Values.serviceAccount.name | quote }}
    namespace: {{ .Release.Namespace | quote }}
{{- end }}
