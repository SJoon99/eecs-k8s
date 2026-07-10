{{- define "omniverse-nucleus.name" -}}
{{- default "omniverse-nucleus" .Values.nucleus.name -}}
{{- end -}}

{{- define "omniverse-nucleus.namespace" -}}
{{- default .Release.Namespace .Values.nucleus.namespace -}}
{{- end -}}

{{- define "omniverse-nucleus.labels" -}}
app.kubernetes.io/name: {{ include "omniverse-nucleus.name" . | quote }}
app.kubernetes.io/part-of: "omniverse"
{{- with .Values.nucleus.labels }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}

{{- define "omniverse-nucleus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "omniverse-nucleus.name" . | quote }}
{{- end -}}

{{- define "omniverse-nucleus.externalHost" -}}
{{- $host := .Values.nucleus.service.externalHost | default .Values.nucleus.service.loadBalancerIP -}}
{{- required "nucleus.service.externalHost or nucleus.service.loadBalancerIP is required" $host -}}
{{- end -}}
