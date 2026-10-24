# Vault on Kubernetes: keep secrets out of the cluster

Companion code for the talk *Your Cluster Secrets Are Not Secret* (Kubernetes Community Days Nigeria 2026). It builds a small, private environment on Google Cloud and walks through three steps:

1. **Kubernetes Secrets aren't secret.** Decode one in a single command, and see who can read it.
2. **Vault KV with the Agent Injector.** Pods log in with their ServiceAccount, secrets land in pod memory, a pod with the wrong identity is refused, and a rotated value reaches the pod without a redeploy.
3. **Dynamic database credentials.** Every pod gets its own short-lived MySQL user, and one command revokes them all.

## Architecture

Nothing has a public IP except one load balancer for the Vault UI:

```
                         ┌──────────────── VPC (no public IPs except the load balancer) ───────────────┐
 browser ─HTTPS─▶ LB ──▶ │ Envoy Gateway (GKE) ─────────┐                                             │
 (allowed IPs only)      │                              ▼                                             │
 laptop ─IAP tunnel────▶ │                     Vault VM :8200 ──TokenReview──▶ GKE control plane       │
                         │                       ▲          └──creates/drops users──▶ Cloud SQL MySQL │
                         │ private GKE nodes ────┘ (vault-agent login + reads)        (private IP)     │
                         │        └──────────────── Cloud NAT (outbound only) ──▶ internet            │
                         └─────────────────────────────────────────────────────────────────────────────┘
```

Vault runs on a VM outside the cluster. The only Vault component inside Kubernetes is the Agent Injector.

## Prerequisites

- A Google Cloud project with billing enabled, and permission to create networks, VMs, GKE clusters and Cloud SQL instances (Owner or Editor is simplest).
- macOS with Homebrew, or Linux with the same tools installed yourself: `gcloud`, `gke-gcloud-auth-plugin`, `kubectl`, `kubectx`, `helm`, `vault`, `jq`, `openssl`.

On macOS, `./setup/00-tools.sh` installs all of them.

## 1. Configure

Edit `config.env`. At minimum, set `PROJECT_ID`. Change `ZONE` if you want a different region. The resource names can stay as they are.

## 2. Create the environment

```sh
gcloud auth login
./setup.sh                   # about 25 minutes
```

| Step | What it creates |
|---|---|
| `setup/01-gke-cluster.sh` | Cloud Router and Cloud NAT; a private GKE Standard cluster (2 × e2-standard-4, nodes without public IPs). `kubectl` uses the IAM-authenticated DNS endpoint, so it works from any network; the IP endpoints only accept the VPC subnet |
| `setup/02-vault-vm.sh` | An e2-small Debian VM running Vault (Raft storage); firewall rules for IAP and GKE → 8200; initializes and unseals Vault |
| `setup/03-injector.sh` | The Vault Helm chart with **only** the Agent Injector, pointed at the VM; a `vault-auth` ServiceAccount for TokenReview |
| `setup/04-cloudsql-mysql.sh` | Private services access; Cloud SQL MySQL 8.0 (db-f1-micro, private IP); `root` and `vault_admin` users; an `orders` database; a `mysql-client` pod for admin queries |
| `setup/05-envoy-gateway.sh` | Envoy Gateway; a `LoadBalancer` restricted to your IP; HTTPS (self-signed) routing to the Vault VM. Prints the UI URL |

Setup writes the unseal key, root token, MySQL passwords and TLS key to `.state/`, which is gitignored. **Never commit `.state/`.**

## 3. Connect to Vault

Vault has no public endpoint. Reach it through an IAP tunnel, in its own terminal, and leave it running:

```sh
./scripts/tunnel.sh          # forwards localhost:8200 to the Vault VM
./scripts/unseal.sh          # only needed if the VM has restarted
```

## 4. Run the walkthrough

Run the steps in order. Step 3 reuses the Kubernetes auth set up in step 2.

| Step | Script | What it does |
|---|---|---|
| 1 | `acts/act1-base64.sh` | Creates an ordinary Kubernetes Secret, decodes it, and shows that the built-in `edit` role can read secrets and create pods |
| 2 | `acts/act2-vault-kv-injector.sh` | Stores config in Vault KV, writes a policy, configures Kubernetes auth and a role, and deploys an annotated app. Shows the injected sidecar, secrets on tmpfs, no Secret objects, a pod with the wrong ServiceAccount refused, and a rotation picked up without a redeploy |
| 3 | `acts/act3-dynamic-db.sh` | Connects Vault's database engine to MySQL, rotates the admin password so only Vault knows it, issues per-pod users with a 2-minute TTL, then revokes every one of them |

Each script prints the next command in yellow and waits for **Enter** before running it. To run one straight through, prefix it with `AUTO=1`:

```sh
AUTO=1 ./acts/act1-base64.sh && AUTO=1 ./acts/act2-vault-kv-injector.sh && AUTO=1 ./acts/act3-dynamic-db.sh
```

What to expect:

- In step 2, the `intruder` pod stays in `Init:0/1` with `403 … service account name not authorized` in its logs. That's the intended result.
- In step 3, after `lease revoke`, the app may log `Access denied` before the agent fetches a new user. Either way, the old users are gone from `mysql.user`.

To run the walkthrough again, reset first:

```sh
./scripts/reset.sh           # removes everything the acts created
```

## 5. Vault UI (optional)

`setup/05-envoy-gateway.sh` prints the URL, `https://<load-balancer-ip>/ui`. Accept the self-signed certificate warning, then sign in with the root token:

```sh
jq -r .root_token .state/vault-init.json
```

The load balancer only accepts the public IP you had during setup. If you change networks, allow your new IP:

```sh
./scripts/allow-my-ip.sh                         # your current public IP (looked up via api.ipify.org)
./scripts/allow-my-ip.sh 1.2.3.4/32,5.6.7.0/24   # or explicit CIDRs; this replaces the list
```

## 6. Clean up

```sh
./scripts/teardown.sh
```

This deletes everything setup created, and `.state/`, except the VPC peering for Cloud SQL's private IP (free, and reused if you set up again). While the environment is running it costs a few dollars a day, which the Google Cloud free trial credit covers. Deleting the whole project also works.

## How it fits together

- **Agents reach Vault** at the VM's internal IP (`global.externalVaultAddr`). The `vault-allow-gke` firewall rule allows port 8200 only from the cluster's pod and node ranges.
- **Vault verifies pod tokens** by calling the GKE control plane's private endpoint with the `vault-auth` ServiceAccount token (`system:auth-delegator`). Step 2 writes the cluster endpoint, CA and that token into `auth/kubernetes/config`.
- **Vault reaches MySQL** on Cloud SQL's private IP, through the VPC peering created by private services access. So do the app pods.
- **You reach Vault** through IAP, so port 8200 is never exposed to the internet.
- **Nodes and the Vault VM** reach the internet (images, packages) through Cloud NAT, which is outbound only.
- **The browser reaches the UI** through the load balancer → Envoy pods in GKE → a `vault-external` Service with no selector (an EndpointSlice points at the VM's private IP) → the Vault VM.

## Not production-ready

This environment takes shortcuts to stay small and quick to build:

- One unseal key, instead of auto-unseal with a KMS
- Plain HTTP between the cluster and Vault, instead of TLS
- A root token on your machine
- Cloud SQL accepts non-TLS connections
- A single Vault node

`vault/vault-server-production.hcl` shows a production configuration: three nodes on integrated Raft storage, TLS, and KMS auto-unseal.

## Layout

```
config.env                  project, zone and resource names
setup.sh                    runs setup/01..05 in order
setup/                      tools, NAT + private GKE, Vault VM, injector, Cloud SQL, Envoy Gateway
acts/                       the walkthrough: act1..act3
scripts/
  lib.sh                    shared helpers (step/say, v = vault CLI, mysql_admin)
  tunnel.sh / unseal.sh     IAP tunnel to the VM; unseal after a restart
  allow-my-ip.sh            let your current network reach the Vault UI
  reset.sh / teardown.sh    back to a clean start; delete everything
manifests/                  Kubernetes YAML used by the acts
vault/                      policies, SQL, VM startup script, injector values, production reference
```
