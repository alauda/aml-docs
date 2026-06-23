# Feast first-cycle e2e smoke (runnable solution)

Roadmap 8.5.2 — *Feature Store GA*. This is a self-contained, egress-free smoke that
takes a brand-new cluster from "no FeatureStore exists" to a verified **online feature
read**, using only cluster-pullable images. It is the runbook behind
`e2e/cases/c13_feast_firstcycle.sh`.

## What it proves

1. The Feast Operator reconciles the **first** `FeatureStore` CR to `status.phase=Ready`
   (it scaffolds a demo feature repo and runs `feast apply` on init).
2. The full feature lifecycle works end-to-end on the same `feature-server` image the
   operator deploys: **synthesize data → `feast apply` → `feast materialize-incremental`
   → `get_online_features()`**, returning the expected value.

All data is generated in-cluster (pandas, bundled in the image). All stores are local
(file registry, file offline, sqlite online). Nothing is pulled from PyPI / docker.io /
HuggingFace.

## Files

| File | Purpose |
| ---- | ------- |
| `operator-install.yaml` | OLM install of the Feast Operator (Namespace + OperatorGroup + Subscription). |
| `featurestore.yaml`     | Minimal all-local PVC-backed `FeatureStore` CR. |
| `online-features-job.yaml` | Single Job that runs the whole online-read lifecycle and asserts the value. |

## Environment facts (g1-c1-x86, validated 2026-06-23)

- CRD `featurestores.feast.dev` is present on `g1-c1-x86` and `g1-c2-arm`.
- Operator package: platform OLM catalog `cpaas-system/platform`, package `feast-operator`,
  channel `alpha`, CSV `feast-operator.v0.63.0-build.20260529061714` (AllNamespaces).
- Operator image: `build-harbor.alauda.cn/mlops/feast/feast-operator:v0.63.0-build.20260529061714`
- Feature-server image: `build-harbor.alauda.cn/mlops/feast/feature-server:0.63.0`
  (feast SDK 0.63.0, Python 3.12; the cluster transparently mirrors this to
  `152-231-registry.alauda.cn:60070/...`). Runs as uid 1001 / gid 0, HOME `/opt/app-root/src`.

> **Operator namespace matters.** The operator must be installed in
> **`feast-operator-system`**. When reconciling a FeatureStore it deploys a shared
> "namespace registry" into its *own* namespace, which it resolves to the upstream default
> `feast-operator-system`. Installed elsewhere, the FeatureStore is stuck `phase=Failed`
> with `namespaces "feast-operator-system" not found`, even though every sub-store reports
> Ready.

## Run it

```bash
CTX=g1-c1-x86-admin@g1-c1-x86
kc() { kubectl --context "$CTX" "$@"; }

# 0. Operator (one-time; skip if already installed in feast-operator-system)
kc apply -f operator-install.yaml
kc -n feast-operator-system rollout status deploy/feast-operator-controller-manager --timeout=300s

# 1. First FeatureStore
kc create ns feast-e2e
kc apply -f featurestore.yaml
# wait until Ready
until [ "$(kc get featurestore feast-e2e -n feast-e2e -o jsonpath='{.status.phase}')" = Ready ]; do sleep 5; done

# 2. Online-read lifecycle (apply -> materialize -> read)
kc apply -f online-features-job.yaml
kc -n feast-e2e wait --for=condition=complete job/feast-online-read --timeout=600s
kc -n feast-e2e logs job/feast-online-read | grep -E 'ONLINE_RESULT|SMOKE_OK'
```

Expected tail:

```text
ONLINE_RESULT: {'driver_id': [1001], 'acc_rate': [0.55...], 'conv_rate': [0.42...], 'avg_daily_trips': [99]}
SMOKE_OK driver_id=1001 conv_rate=0.42...
```

## Clean up

```bash
kc delete ns feast-e2e --wait=false      # FeatureStore CR, PVCs, Jobs
# operator (feast-operator-system) is left installed as a platform component
```

## Or via the harness

```bash
cd e2e && ./run_all.sh C13          # exits 77 (SKIP) if operator/CRD/image is missing
```
