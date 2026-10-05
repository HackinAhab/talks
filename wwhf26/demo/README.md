# BloodHound-Kube Conference Demo

This is an intentionally insecure, local-only Kubernetes lab for demonstrating BloodHound-Kube across two `kind` clusters. It creates synthetic attack paths; it is not an exploitation guide and must not be deployed to a real cluster.

| Cluster | kubectl context | Demo endpoint | Attack path manifest |
| --- | --- | --- | --- |
| `bhk-demo` | `kind-bhk-demo` | `http://127.0.0.1:8081` | `manifests/node-path.yaml` |
| `bhk-demo-2` | `kind-bhk-demo-2` | `http://127.0.0.1:8082` | `manifests/secret-path.yaml` |

Each cluster has a control-plane node and a worker. Each manifest defines a different path in the `bhk-demo` namespace; unique cluster names keep identically named resources distinct in the graph.

## What the graph shows

`bhk-demo` (`manifests/node-path.yaml`) models node impact via a privileged Pod and kubelet host mount:

```text
External -> NodePort Service -> privileged Pod -> kind Node
```

`bhk-demo-2` (`manifests/secret-path.yaml`) models identity-based access: the Pod's ServiceAccount has `get` access to one fake Secret, without the privileged container or host mount:

```text
External -> NodePort Service -> Pod -> ServiceAccount -> synthetic Secret
```

All data in the lab is synthetic. Secret redaction is controlled by `defaults.redacted` in `clusters.yml`, currently set to `false`.

## Prerequisites

- Docker with at least 8 GB of memory available to BloodHound CE, plus capacity for four `kind` nodes.
- [`kind`](https://kind.sigs.k8s.io/) and [`kubectl`](https://kubernetes.io/docs/tasks/tools/).
- Bash and `curl` on Linux or macOS. On Windows, use WSL2.
- BloodHound-Kube with `collect --clusters-config` support (check `bloodhound-kube collect --help`). Use a current release binary or an embedded build from `main`:

```bash
git clone https://github.com/HackinAhab/bloodhound-kube.git
cd bloodhound-kube
go build -tags embedded -o bloodhound-kube
```

For a release binary, set `BHK_BIN` to its path before running the collection commands below.

## Start the lab

From this directory:

```bash
chmod +x scripts/*.sh
./scripts/demo.sh up
./scripts/demo.sh verify
```

`up` creates both clusters, applies each cluster's attack-path manifest, and exports separate minified kubeconfigs into `output/`. It reuses existing demo clusters and removes the legacy Secret-path resources from `bhk-demo`. `verify` confirms the ServiceAccount's permission to read the named synthetic Secret in `bhk-demo-2` and checks both locally bound demo endpoints.

## Start BloodHound CE

The bundled Compose stack is based on the official BloodHound CE Compose example and pins BloodHound CE to `v9.7.1`. It only binds the web interface to `127.0.0.1:8080`.

```bash
./scripts/bloodhound.sh up
./scripts/bloodhound.sh logs
```

Wait until the log shows that the server started successfully. The initial admin password is also printed there. Sign in at <http://127.0.0.1:8080/ui/login>, then change the password when prompted.

Create an API token in the BloodHound administration UI and retain its token ID and token key only in your terminal environment:

```bash
export BLOODHOUND_TOKEN_ID='...'
export BLOODHOUND_TOKEN_KEY='...'
```

## Collect and upload

The command refreshes each cluster's kubeconfig and invokes `bloodhound-kube collect --clusters-config clusters.yml` once. The config sets shared collection defaults and explicit per-cluster paths:

- `output/bhk-demo.kubeconfig` → `output/bhk-demo.jsonl` → `output/bhk-demo.json`
- `output/bhk-demo-2.kubeconfig` → `output/bhk-demo-2.jsonl` → `output/bhk-demo-2.json`

`output/` is ignored by Git because the kubeconfigs contain sensitive local-cluster material.

```bash
export BHK_BIN=/absolute/path/to/bloodhound-kube
./scripts/demo.sh collect
./scripts/demo.sh upload
```

To show the tool's multi-cluster command directly after `up`, run this from `demo/`:

```bash
"${BHK_BIN}" collect --clusters-config clusters.yml
```

The upload command enables OpenGraph extension management, uploads the embedded BloodHound-Kube schema, merges the three lab queries with the binary's embedded queries, and uploads both clusters' graph files.

In BloodHound, open **Explore** and run **BHK Demo: External to Privileged Node Path** for `bhk-demo`, then **BHK Demo: External to Synthetic Secret** for `bhk-demo-2`. The saved lab queries filter to their respective clusters; **BHK Demo: Risky Workload Configuration** is also scoped to `bhk-demo`. The binary's embedded queries are uploaded with `bhk-demo` as their cluster. Explain that edges are test leads: real impact must always be validated against the target environment.

## Reset and teardown

```bash
./scripts/demo.sh down
./scripts/bloodhound.sh down
```

To erase all BloodHound data and create a new admin password on the next start:

```bash
./scripts/bloodhound.sh reset
```

`demo.sh down` deletes both demo clusters.

## Troubleshooting

- `kind create cluster` fails: ensure Docker is running, then run `./scripts/demo.sh down` before retrying.
- The Pod never becomes ready: check `kubectl --context kind-bhk-demo -n bhk-demo get pods` (or context `kind-bhk-demo-2`); image pulls require internet access.
- BloodHound exits during startup: increase Docker's memory allocation to at least 8 GB and wait about a minute after startup before API uploads.
- `upload` fails with an authentication error: create a new BloodHound API token and export both values again. Do not use the browser login password as a token key.
- `BHK_BIN` is not found: either add the binary to `PATH` or set `BHK_BIN` to its absolute path.
- `--clusters-config` is unknown: update BloodHound-Kube to a version with multi-cluster collection support.
- Direct collection cannot find a kubeconfig: run `./scripts/demo.sh up` first and invoke the direct collection command from `demo/`; paths in `clusters.yml` are relative to the working directory.

## Safety boundary

The `public-web` workload in `bhk-demo` is deliberately privileged and mounts `/var/lib/kubelet`. The second cluster contains a fake Secret and an intentionally scoped RBAC grant. The Compose stack contains local development database passwords. Keep the lab on an isolated development workstation, leave the default localhost bindings intact, and destroy it when finished.
