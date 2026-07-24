# Temporal namespace and Nexus bootstrap

This ArgoCD PostSync Job idempotently creates the logical Temporal namespaces
and internal Nexus endpoints used by the local cluster.

| Endpoint | Target namespace | Handler task queue |
| --- | --- | --- |
| `ob1-nexus-comms-cluster-1-endpoint-1` | `ob1-temporal-comms-cluster-1-ns-1` | `ob1-comms-nexus-queue-1` |
| `ob1-nexus-llm-cluster-1-endpoint-1` | `ob1-temporal-llm-router-1-ns-1` | `ob1-llm-router-nexus-queue-1` |
| `ob1-uo-temporal-budytest1-gilfoyletest1-1-1` | `ob1-uo-temporal-budytest1-ns-1` | `ob1-budytest1-nexus-queue-1` |
| `ob1-uo-temporal-hawthorn-hope-1-1` | `ob1-uo-temporal-hawthorn-ns-1` | `ob1-hawthorn-hope-nexus-queue-1` |

Future local Nexus handler workers must poll the matching handler task queue in
the mapped Temporal namespace.
