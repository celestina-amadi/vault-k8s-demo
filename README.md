# Demo: Your Cluster Secrets Are Not Secret

Live demo for the talk, built to mirror a production layout on GCP. Nothing has a public IP except one load balancer for the Vault UI:

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

| Act | Script | Shows | Time |
|---|---|---|---|
| 1 | `act1-base64.sh` | A Kubernetes Secret decoded in one command; who can read it | ~3 min |
| 2 | `act2-vault-kv-injector.sh` | KV paths, policy, Kubernetes auth against an external Vault, injector annotations, tmpfs, an unauthorized pod being refused, rotation without a redeploy | ~10 min |
| 3 | `act3-dynamic-db.sh` | Database engine on Cloud SQL MySQL, root rotation, short-lived users, revoking all of them in one command | ~5 min |

Each script prints the next command in yellow and waits for **Enter** before running it. `AUTO=1 ./act2-vault-kv-injector.sh` runs without pauses for rehearsal.

## One-time setup

```sh
./setup/00-tools.sh          # helm, gcloud, vault CLI, gke-gcloud-auth-plugin
gcloud auth login            # browser sign-in
# edit config.env: PROJECT_ID (and ZONE if you want one closer to the venue)
./setup.sh                   # ~25 min: NAT, private GKE, Vault VM, injector, Cloud SQL, Envoy Gateway
```

What `setup.sh` creates:

| Step | Resource |
|---|---|
| `01-gke-cluster.sh` | Cloud Router + Cloud NAT; private GKE Standard cluster (2 × e2-standard-4, nodes without public IPs). `kubectl` uses the IAM-authenticated DNS endpoint, so it works from any network; the IP endpoints only accept the VPC subnet |
| `02-vault-vm.sh` | e2-small Debian VM **with no public IP** running Vault (Raft storage), firewall rules for IAP and GKE → 8200; initializes and unseals Vault |
| `03-injector.sh` | Helm chart with **only** the Agent Injector, pointed at the VM; `vault-auth` ServiceAccount for TokenReview |
| `04-cloudsql-mysql.sh` | Private services access, Cloud SQL MySQL 8.0 (db-f1-micro, private IP), `root` and `vault_admin` users, `orders` database, a `mysql-client` pod for admin queries |
| `05-envoy-gateway.sh` | Envoy Gateway, a `LoadBalancer` restricted to your IP, HTTPS (self-signed) routing to the Vault VM; prints the UI URL |

Secrets created by setup (unseal key, root token, MySQL passwords) are written to `.state/`, which is gitignored. **Never commit `.state/`.**

Rough cost while running: a few dollars a day, covered by the GCP free trial credit. Run `./teardown.sh` when you're finished.

## Every session

```sh
./tunnel.sh                  # in its own tab; leave it running
./unseal.sh                  # only needed if the VM restarted
./reset.sh                   # back to a clean starting state
```

Rehearse, then reset:

```sh
AUTO=1 ./act1-base64.sh && AUTO=1 ./act2-vault-kv-injector.sh && AUTO=1 ./act3-dynamic-db.sh
./reset.sh
```

## Vault UI in the browser

`setup/05-envoy-gateway.sh` prints the URL: `https://<load-balancer-ip>/ui`. Accept the self-signed certificate warning, then sign in with the root token (`jq -r .root_token .state/vault-init.json`).

The load balancer only accepts your public IP at setup time. **At the venue, run `./allow-my-ip.sh`** to allow the venue network instead (or pass CIDRs: `./allow-my-ip.sh 1.2.3.4/32,5.6.7.0/24`).

Path: browser → GCP load balancer → Envoy pods in GKE → `vault-external` Service (no selector; an EndpointSlice points at the VM's private IP) → Vault VM.

## Layout

```
config.env                  project / zone / names
lib.sh                      step/say helpers, v = vault CLI, mysql_admin
tunnel.sh / unseal.sh       IAP tunnel to the VM; unseal after a reboot
allow-my-ip.sh              let your current network reach the Vault UI
setup/                      tools, NAT + private GKE, Vault VM, injector, Cloud SQL, Envoy Gateway
manifests/                  Kubernetes YAML used by the acts
vault/                      policies, SQL, VM startup script, injector values, production reference
act1..act3                  the on-stage scripts
reset.sh / teardown.sh
```

## How the external-Vault parts fit

- **Agents reach Vault** at the VM's internal IP (`global.externalVaultAddr`). Firewall rule `vault-allow-gke` allows port 8200 only from the cluster's pod and node ranges.
- **Nothing has a public IP** except the Envoy load balancer. Nodes and the Vault VM reach the internet (images, packages) through Cloud NAT, which is outbound only.
- **Vault verifies pod tokens** by calling the GKE control plane's **private endpoint** with the `vault-auth` ServiceAccount token (`system:auth-delegator`). Act 2 writes the cluster endpoint, CA and that token into `auth/kubernetes/config`.
- **Vault reaches MySQL** on Cloud SQL's private IP, through the VPC peering created by private services access. So do the app pods.
- **You reach Vault** through IAP (`./tunnel.sh`), so port 8200 is never exposed to the internet.

## Notes for the stage

- **Demo shortcuts, say them out loud:** one unseal key instead of Cloud KMS auto-unseal, plain HTTP inside the VPC instead of TLS, a root token on the laptop, Cloud SQL accepting non-TLS connections. `vault/vault-server-production.hcl` shows the production version.
- **Be precise about "unencrypted".** On GKE, etcd is encrypted at rest by default, and you can add application-layer secrets encryption with Cloud KMS. The real exposure is RBAC `get`/`list` on secrets, anyone who can create pods in the namespace, Git, backups and logs. Expect this question.
- `kubectl` connects through the cluster's DNS endpoint, which checks your Google sign-in rather than your IP, so nothing changes at the venue. Vault calls the control plane's private endpoint; the VPC subnet is in its authorized networks.
- The Vault UI is reachable only from allowed IPs. Run `./allow-my-ip.sh` once you're on the venue network.
- The intruder pod in Act 2 stays in `Init:0/1`. That is the intended result.
- In Act 3, after `lease revoke`, the agent may fetch new credentials before the app logs a failure. Either result works: the old users are gone from `mysql.user` either way.

## Preparation checklist

**Logistics**
- [ ] Confirm slot length, whether there's Q&A, and the AV setup (HDMI or USB-C, resolution, mirroring or extended display)
- [ ] Ask whether venue Wi-Fi is reliable; plan to tether to your phone (the IAP tunnel needs internet)
- [ ] Find out whether talks are recorded, and whether the organizers want slides in advance

**Demo safety**
- [ ] Run `setup.sh` at least a day before. Don't create anything on stage.
- [ ] Record a full run of the demo as an offline fallback
- [ ] Take screenshots of key outputs (decoded secret, `df` showing tmpfs, intruder denied, `mysql.user` list) as a second fallback
- [x] Vault Helm chart pinned to 0.34.1, Envoy Gateway to v1.4.0
- [ ] Morning of the talk: `./tunnel.sh`, `./unseal.sh`, run every act once, `./reset.sh`
- [ ] Check `gcloud auth` hasn't expired that morning (`kubectl get nodes`)
- [ ] On the venue network: `./allow-my-ip.sh`, then open the Vault UI once to accept the certificate

**Terminal**
- [ ] Font size 20pt or larger, dark background, high contrast
- [ ] Short prompt (`PS1='$ '`), notifications off
- [ ] Three tabs: the tunnel, the scripts, and optionally `kubectl get pods -A -w`

**Content**
- [ ] Rehearse the full talk out loud at least 3 times with a timer
- [ ] Prepare answers for likely questions: GKE etcd encryption, External Secrets Operator, Secrets Store CSI driver, Google Secret Manager, what happens if Vault is down, sidecar overhead, why Vault on VMs instead of in the cluster
