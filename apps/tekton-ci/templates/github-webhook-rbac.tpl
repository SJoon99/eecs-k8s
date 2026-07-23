{{- if .Values.githubWebhook.enabled }}
{{- $sa := required "githubWebhook.names.serviceAccount is required" .Values.githubWebhook.names.serviceAccount }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $sa | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ printf "%s-eventlistener" $sa | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
subjects:
  - kind: ServiceAccount
    name: {{ $sa | quote }}
    namespace: {{ .Release.Namespace | quote }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ printf "%s-%s-eventlistener" .Release.Name .Release.Namespace | trunc 63 | trimSuffix "-" | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
subjects:
  - kind: ServiceAccount
    name: {{ $sa | quote }}
    namespace: {{ .Release.Namespace | quote }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-clusterroles
{{- end }}
