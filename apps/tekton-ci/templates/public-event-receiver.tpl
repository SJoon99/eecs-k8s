{{- if .Values.publicEventReceiver.enabled }}
{{- $cfg := .Values.publicEventReceiver }}
{{- $listener := required "publicEventReceiver.eventListenerName is required" $cfg.eventListenerName }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ required "publicEventReceiver.service.name is required" $cfg.service.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/managed-by: EventListener
    app.kubernetes.io/part-of: Triggers
    eventlistener: {{ $listener | quote }}
  ports:
    - name: http-listener
      protocol: TCP
      port: {{ required "publicEventReceiver.service.port is required" $cfg.service.port }}
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ required "publicEventReceiver.networkPolicy.name is required" $cfg.networkPolicy.name | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/managed-by: EventListener
      app.kubernetes.io/part-of: Triggers
      eventlistener: {{ $listener | quote }}
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 8080
{{- end }}
