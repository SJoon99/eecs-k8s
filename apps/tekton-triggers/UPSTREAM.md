# Tekton Triggers upstream bundle

- Version: `v0.36.0`
- Release: `https://infra.tekton.dev/tekton-releases/triggers/previous/v0.36.0/release.yaml`
- Release SHA-256: `b1ddfa9b630f345bf70759c267ce42ef296b90beaf7308780db86cde7c0c38de`
- Interceptors: `https://infra.tekton.dev/tekton-releases/triggers/previous/v0.36.0/interceptors.yaml`
- Interceptors SHA-256: `4ba57d4c66d2db457309aa2483f3829c4248091a4f9f99d1f0d2b41d7aaa7379`
- Update rule: replace both files together and update `Chart.yaml` versions.

The files under `upstream/` are vendored unchanged so Argo CD can reconcile a
pinned, reviewable release without downloading mutable `latest` manifests.
