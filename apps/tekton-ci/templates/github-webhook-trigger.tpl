{{- if .Values.githubWebhook.enabled }}
{{- $cfg := .Values.githubWebhook }}
{{- $repo := required "githubWebhook.repository.fullName is required" $cfg.repository.fullName }}
{{- $branch := required "githubWebhook.repository.branchRef is required" $cfg.repository.branchRef }}
{{- $child := required "githubWebhook.pipeline.childName is required" $cfg.pipeline.childName }}
{{- $chartPath := required "githubWebhook.pipeline.chartPath is required" $cfg.pipeline.chartPath }}
{{- $storageClass := required "githubWebhook.pipeline.workspace.storageClassName is required" $cfg.pipeline.workspace.storageClassName }}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: {{ $cfg.names.triggerBinding | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  params:
    - name: child-name
      value: {{ $child | quote }}
    - name: repo-url
      value: $(body.repository.clone_url)
    - name: source-revision
      value: $(body.after)
    - name: chart-path
      value: {{ $chartPath | quote }}
    - name: build-targets
      value: {{ required "githubWebhook.pipeline.buildTargets is required" $cfg.pipeline.buildTargets | quote }}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: {{ $cfg.names.triggerTemplate | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  params:
    - name: child-name
    - name: repo-url
    - name: source-revision
    - name: chart-path
    - name: build-targets
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: {{ printf "%s-github-" $child | quote }}
        namespace: {{ .Release.Namespace | quote }}
        labels:
          app.kubernetes.io/part-of: tekton-ci
          scalex.io/child-name: $(tt.params.child-name)
          tekton.dev/pipeline: {{ $cfg.pipeline.name | quote }}
          triggers.tekton.dev/eventlistener: {{ $cfg.names.eventListener | quote }}
      spec:
        pipelineRef:
          name: {{ $cfg.pipeline.name | quote }}
        params:
          - name: child-name
            value: $(tt.params.child-name)
          - name: repo-url
            value: $(tt.params.repo-url)
          - name: source-revision
            value: $(tt.params.source-revision)
          - name: chart-path
            value: $(tt.params.chart-path)
          - name: build-targets
            value: $(tt.params.build-targets)
        taskRunTemplate:
          serviceAccountName: {{ $cfg.pipeline.runnerServiceAccount | quote }}
          podTemplate:
            securityContext:
              fsGroup: 65532
              fsGroupChangePolicy: OnRootMismatch
        timeouts:
          pipeline: {{ $cfg.pipeline.timeout | quote }}
        workspaces:
          - name: source
            volumeClaimTemplate:
              metadata:
                labels:
                  app.kubernetes.io/part-of: tekton-ci
              spec:
                accessModes:
{{- toYaml $cfg.pipeline.workspace.accessModes | nindent 18 }}
                resources:
                  requests:
                    storage: {{ $cfg.pipeline.workspace.size | quote }}
                storageClassName: {{ $storageClass | quote }}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: {{ $cfg.names.eventListener | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  namespaceSelector: {}
  resources: {}
  serviceAccountName: {{ $cfg.names.serviceAccount | quote }}
  triggers:
    - name: github-push
      interceptors:
        - ref:
            kind: ClusterInterceptor
            name: github
          params:
            - name: secretRef
              value:
                secretName: {{ $cfg.secret.name | quote }}
                secretKey: {{ $cfg.secret.key | quote }}
            - name: eventTypes
              value:
                - push
        - name: expected-repository-and-branch
          ref:
            kind: ClusterInterceptor
            name: cel
          params:
            - name: filter
              value: {{ printf "body.repository.full_name == '%s' && body.ref == '%s' && body.deleted == false" $repo $branch | quote }}
      bindings:
        - kind: TriggerBinding
          ref: {{ $cfg.names.triggerBinding | quote }}
      template:
        ref: {{ $cfg.names.triggerTemplate | quote }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $cfg.names.ingressNetworkPolicy | quote }}
  namespace: {{ .Release.Namespace | quote }}
  labels:
{{- include "tekton-ci.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      eventlistener: {{ $cfg.names.eventListener | quote }}
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 8080
{{- end }}
