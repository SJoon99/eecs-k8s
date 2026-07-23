apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: federation-promote-temp-poc-
  namespace: tower-ci
  labels:
    app.kubernetes.io/part-of: tekton-ci
    scalex.io/child-name: temp-poc
spec:
  pipelineRef:
    name: federation-promote
  taskRunTemplate:
    serviceAccountName: tekton-ci-runner
  params:
    - name: payload
      value: '__PROMOTION_PAYLOAD_JSON__'
