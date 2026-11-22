# gjallar-helm

Helm chart, admission policies and identity setup for
[Gjallar](https://github.com/heimdallr-dev/gjallar).
*Security without chains: see clearly, understand why, and stay free to choose.*

| Path | What |
|---|---|
| `charts/gjallar` | The chart: every component is its own pod; every feature is a value you can turn off |
| `charts/gjallar/values-kind.yaml` | One-node profile (one replica each, small requests) for kind or a homelab |
| `policies/kyverno` | Kyverno ≥ 1.16 `ValidatingPolicy`: admission gate (urgent / known-exploited images) and baseline. Audit mode and `failurePolicy: Ignore` by default. Using OPA, Conftest or Gatekeeper instead? See [gjallar-opa](https://github.com/heimdallr-dev/gjallar-opa) |
| `keycloak/gjallar-realm.json` | Realm with roles, groups claim and audience; works as a template for any OIDC provider |
| `keycloak/keycloak-dev.yaml` | Throwaway dev Keycloak for local clusters (not for production) |

## Install

```bash
# released chart (signed OCI artifact)
helm install gjallar oci://ghcr.io/heimdallr-dev/charts/gjallar --version 0.1.0 -n gjallar --create-namespace -f my-values.yaml
cosign verify ghcr.io/heimdallr-dev/charts/gjallar:0.1.0 \
  --certificate-identity-regexp 'https://github.com/heimdallr-dev/gjallar-helm/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# from source
helm install gjallar charts/gjallar -n gjallar --create-namespace -f my-values.yaml
kubectl apply -f policies/kyverno/      # optional admission policies (Audit)
```

Every value is documented inline in `charts/gjallar/values.yaml`; the full
guide is in [gjallar-docs](https://github.com/heimdallr-dev/gjallar-docs)
(install, configuration, operations).

Nothing in the chart phones home. Every outbound connection is listed under
*Network egress* in the operations guide, with a mirror option for each.

## Dashboard

`charts/gjallar/files/gjallar-dashboard.json` is a copy of the canonical
dashboard in [gjallar-grafana](https://github.com/heimdallr-dev/gjallar-grafana);
update it there and copy it here.

## Licence

Apache-2.0.
