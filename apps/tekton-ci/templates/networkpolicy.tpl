{{- if .Values.networkPolicy.enabled }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ required "networkPolicy.name is required" .Values.networkPolicy.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
{{- end }}
