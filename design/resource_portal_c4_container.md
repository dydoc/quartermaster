# Resource Portal — Container Diagram

![Resource Portal — C4 Container Diagram](./images/C4Container_ResourcePortal.svg)

## Overview

The Resource Portal is deployed as a set of Kubernetes workloads on the Rancher management cluster. At this level the system decomposes into two runtime processes — the **Web Application** and the **Approval Controller** — and three **Custom Resource Definitions** that live on the management cluster and act as the shared, durable data layer between them.

The boundary is the management cluster itself. There are no databases, message queues, or external storage services: Kubernetes etcd (via the CRD API) is the single source of truth for all portal state.

A key security boundary runs through this diagram: **user identity is used only for operations on the management cluster** (Web App authenticating as the logged-in user via Rancher), while **the Approval Controller acts under its own dedicated service account** when applying CRDs on target downstream clusters. End users hold no permissions on those clusters for the resource types exposed by the portal. This is the architectural guarantee that prevents bypassing the approval workflow.

## Containers

### Web Application

The Web Application is a Go monolith that serves all HTTP traffic. It is server-side rendered using the standard `html/template` package — there is no separate frontend bundle or SPA framework. A single process handles session management, OIDC authentication, catalogue browsing, request submission, approval actions, and status display.

At startup the Web App launches a **informer** for both `ResourceRequest` and `ProvisionedResource` objects. The informer maintains a local in-memory cache kept in sync by the Kubernetes watch mechanism. When a user navigates to their resource list, the Web App reads directly from that cache — no polling, no per-request API calls to the cluster.

At submission time the Web App is responsible for **resolving the approver list**: it reads the relevant `ResourceCatalogue` entry, evaluates the approval routing rule (which may reference LDAP groups, team labels, or explicit user lists), expands it into a concrete list of approver identities, and embeds that list in the `ResourceRequest` it writes. The Approval Controller consumes the list as data — it never re-evaluates routing rules itself.

### Approval Controller

The Approval Controller is a standard Kubernetes controller built with `controller-runtime`. It watches `ResourceRequest` objects and reacts to status transitions driven by Approver actions in the Web App.

The controller's reconcile loop is deliberately policy-agnostic: the approval policy is carried as structured data inside the `ResourceRequest` spec and evaluated at submission time by the Web App. The controller reads the pre-resolved approver list and the current approval decisions, and advances the state machine accordingly — without any hardcoded routing logic.

The controller's **only write to a target cluster** is creating, updating, or deleting the **CRD target instance** (e.g. a `NamespaceRequest`), authenticated as its own dedicated Kubernetes service account through Rancher. It never touches the derived objects that the CRD target instance produces — Pods, Services, ConfigMaps, or any other resource. Those are the exclusive responsibility of the CRD target controller on the target cluster.

In addition to driving provisioning, the controller runs a **Health Observer** on every reconcile pass for all `ProvisionedResource` objects in `provisioned` or `updating` phase. The Health Observer reads the `status.conditions` of the CRD target instance on the downstream cluster (read-only via Rancher) and updates `ProvisionedResource.status.phase` to `degraded` or `unknown` if the instance has become unhealthy or has disappeared. If the CRD target instance was deleted out-of-band — not through a portal `delete` request — the Health Observer re-applies it via SSA to restore it. This is the only form of drift correction the Approval Controller performs, and it operates at the CRD target instance level only, never on derived objects.

### Integrity of derived objects: SSA with field ownership and drift reconciliation

Applying the CRD target instance is only the first step. The CRD target controller on the downstream cluster will in turn create derived objects — Pods, Services, ConfigMaps, PVCs, or any other Kubernetes resource the resource type requires. An end user with standard namespace permissions could modify those derived objects directly, bypassing the portal's governance entirely.

The mechanism that prevents this is **not** something the Approval Controller does. It is a property of the CRD target controller — and it is enforced through the onboarding contract, not at runtime by the portal.

**Server-Side Apply (SSA) with field ownership.** The CRD target controller applies all derived objects using SSA, declaring itself as the field manager on every configuration-significant field. Once a field is owned by the CRD target controller's field manager, any attempt by another actor to patch that field without using `--force` is rejected by the API server with a conflict error. This makes out-of-band modification of critical fields fail immediately and visibly.

**Active drift reconciliation.** The CRD target controller does not treat the initial apply as a one-time operation. On every reconcile loop — triggered by watch events or periodic resync on the target cluster — it re-applies the full desired state of all derived objects via SSA. If a user has forced a field override, the next reconcile restores the correct state. The reconcile window is the only gap in protection; under normal conditions it is measured in seconds.

**CEL immutability on the CRD target spec.** The fields of the CRD target itself that determine the configuration of derived objects are marked immutable after creation using `x-kubernetes-validations` CEL rules:

```yaml
x-kubernetes-validations:
  - rule: "self.image == oldSelf.image"
    message: "field is immutable after creation"
```

This prevents any actor from modifying the declared desired state of a provisioned resource without going through a new `ResourceRequest`. Even if someone obtained write access to the CRD target directly, the API server would reject the modification.

**The accepted trade-off.** This strategy accepts a reconcile window during which a forced modification to a derived object is live before being corrected by the CRD target controller. The strategy does not cover `DELETE` of derived objects synchronously — if a user deletes a Pod it will be recreated on the next reconcile pass of the CRD target controller, but it is absent during that window.

### Contract for CRD target authors

Because the integrity guarantees depend on how each CRD target controller is implemented, the portal defines an onboarding contract that every CRD type must satisfy to be admitted to the catalogue:

- all derived objects must be created and updated via SSA, never with imperative `Create` followed by silent drift
- field ownership must be declared on every configuration-significant field, not just top-level spec fields
- the reconcile loop must compare observed vs desired state on all owned fields, not only check object existence
- CEL immutability rules must be defined on all CRD target spec fields that influence derived object configuration

### ResourceRequest CRD

`ResourceRequest` is the central object in the system. It represents the full lifecycle of a single resource request and carries all state needed by both the Web App and the Approval Controller without any further lookup.

The `action` field distinguishes three semantics: `create` (first provisioning), `update` (modification of an already-provisioned resource), and `delete` (deprovisioning). For `update` and `delete`, the `targetRef` field identifies the `ProvisionedResource` being acted upon, carrying both name and UID — the UID prevents the controller from acting on a different object that happens to share the same name.

For `update` actions, the Web App snapshots the current `appliedParameters` from the `ProvisionedResource` into a `previousParameters` field at submission time. This lets the approver see exactly what is changing and gives the controller a deterministic rollback target if the update fails.

Fields carried by a `ResourceRequest`:

- `spec.action` — `create` | `update` | `delete`
- `spec.targetRef.name` / `spec.targetRef.uid` — present for `update` and `delete`
- `spec.resourceType` — references a `ResourceCatalogue` entry
- `spec.parameters` — the desired configuration
- `spec.previousParameters` — snapshot of current configuration at submission time (update only)
- `spec.approvalPolicy` — snapshot of the policy from `ResourceCatalogue` at submission time
- `spec.approvers` — pre-resolved list of required approver identities
- `status.phase` — `pending` → `approved` / `rejected` → `provisioning` → `provisioned` / `failed`
- `status.decisions` — one entry per approver action, with identity and timestamp
- `status.failureReason` — populated on `failed`

### ProvisionedResource CRD

`ProvisionedResource` is the management-cluster's authoritative record of a resource that has been successfully provisioned on a target cluster. It is written and owned exclusively by the Approval Controller — the Web App and users never write to it directly.

The controller updates `ProvisionedResource` only after observing that the CRD target instance on the downstream cluster has reached a `Ready` state — not optimistically at the moment of apply. This means `ProvisionedResource` always reflects the last confirmed operational state. During an in-flight update the object retains the previous `appliedParameters` until the new ones are confirmed; if the update fails the controller uses those parameters as the rollback target.

The `ProvisionedResource` carries a finalizer added by the controller at creation time. The finalizer is removed only after the controller has confirmed that the CRD target instance on the downstream cluster has been successfully deleted.

Fields carried by `ProvisionedResource`:

- `spec.resourceType` — the CRD type that was provisioned
- `spec.targetCluster` — the downstream cluster where the resource lives
- `spec.targetRef` — GVR + namespace + name of the CRD target instance
- `spec.appliedParameters` — the parameters currently confirmed operational
- `status.phase` — `provisioned` | `updating` | `degraded` | `deleting`
- `metadata.labels`:
  - `portal.example.com/resource-type` — for filtering by type in the informer cache
  - `portal.example.com/created-by-request` — UID of the originating `create` ResourceRequest
  - `portal.example.com/last-updated-by-request` — UID of the most recent successful `update` ResourceRequest

The label-based cross-reference allows the Web App to retrieve the full history of `ResourceRequest` objects associated with a given `ProvisionedResource` via a single label selector query on the informer cache, without any additional API server calls.

### ResourceCatalogue CRD

`ResourceCatalogue` defines what resources are available for request. Each entry describes a resource type (name, schema, target cluster scope), the quota limits that apply, and the approval routing rule (which group or identity must approve requests of this type). Platform Admins manage these objects through the Web App's administration interface. The Web App reads the catalogue at submission time to validate the request and resolve the approver list.

### Mail Relay

An SMTP relay — either an in-cluster relay or an external SMTP gateway — used exclusively by the Approval Controller to deliver state-change notifications. The relay has no knowledge of portal state; it receives a plain SMTP message and delivers it. Retry and backoff are handled by the controller, not the relay.

## Data Flows

### Happy Path — create

1. **End User** logs in via OIDC (Web App ↔ Identity Provider).
2. **End User** browses the catalogue (Web App reads `ResourceCatalogue`).
3. **End User** submits a request. Web App resolves the approver list, creates a `ResourceRequest` (`action: create`) in `pending` phase.
4. **Approver** sees the pending request, approves it. Web App records the decision in the `ResourceRequest`.
5. Approval Controller detects the transition, advances phase to `provisioning`, applies the target-cluster CRD via Rancher as controller service account.
6. Controller watches the CRD target instance until it reaches `Ready`. On confirmation, writes `ProvisionedResource` with `appliedParameters`, advances `ResourceRequest` phase to `provisioned`, sends notification email.
7. **End User** sees `provisioned` status from the informer cache, no polling.

### Happy Path — update

1. **End User** selects an existing provisioned resource and submits a modification.
2. Web App checks that no other `ResourceRequest` is in a non-terminal phase for the same `ProvisionedResource`. If one exists, submission is rejected with an explicit message.
3. Web App snapshots `appliedParameters` into `previousParameters`, creates a `ResourceRequest` (`action: update`, `targetRef` with UID).
4. **Approver** sees a diff view (new parameters vs `previousParameters`), approves it.
5. Controller advances to `provisioning`, applies the updated CRD target instance via SSA.
6. Controller watches for `Ready` confirmation. On success, updates `ProvisionedResource` with new `appliedParameters`, sends notification.
7. **End User** sees updated state from informer cache.

### Failure Path — update with rollback

1. Controller applies updated CRD target instance; downstream controller fails to reconcile.
2. Controller retries with exponential backoff.
3. After exhausting retries, controller re-applies `previousParameters` from the `ResourceRequest` to restore the CRD target instance to its pre-update state via SSA.
4. `ProvisionedResource` is never modified — it still carries the last confirmed `appliedParameters`.
5. Controller sets `ResourceRequest` phase to `failed` with `failureReason`, sends notification email.
6. Web App shows `failed` on the update request; `ProvisionedResource` still shows `provisioned` with the previous parameters — no inconsistent state visible to the user.

### Deprovisioning

1. **End User** requests deletion of a provisioned resource.
2. Web App creates a `ResourceRequest` (`action: delete`, `targetRef` with UID).
3. After approval, controller advances to `provisioning`, sets `ProvisionedResource` phase to `deleting`.
4. Controller deletes the CRD target instance on the downstream cluster via Rancher.
5. Controller watches for the CRD target instance to disappear. On confirmation, removes the finalizer from `ProvisionedResource` — the GC deletes it.
6. Controller advances `ResourceRequest` phase to `provisioned` (the delete action completed successfully), sends notification.

## Key Design Decisions

**Dual identity, explicit boundary.** The Web App uses the logged-in user's identity for all management-cluster operations so that every user action is fully auditable through standard Kubernetes audit logs. The Approval Controller uses a dedicated service account with narrow RBAC on target clusters for the provisioning step. End users have no `create`/`patch` permissions on the CRD types managed by the portal on those clusters. The portal is not a convenience layer over existing user permissions — it is the only path.

**SSA field ownership + drift reconciliation over admission webhook.** The integrity of derived objects on target clusters is enforced through the CRD target controller using Server-Side Apply with explicit field ownership combined with active drift reconciliation on every resync — not by the Approval Controller and not by a ValidatingAdmissionWebhook. The Approval Controller's scope ends at the CRD target instance; everything below that is the CRD target controller's responsibility, enforced by the onboarding contract. The trade-offs accepted: the reconcile window (seconds) is the gap in protection, and synchronous DELETE coverage is not provided. In exchange, there is no additional webhook component to operate on each target cluster, no Fail Open/Fail Closed availability dilemma, and no bootstrap ordering dependency.

**CRD target onboarding contract.** Because the integrity guarantees depend on correct implementation of SSA and drift reconciliation in each CRD target controller, the portal defines an explicit onboarding contract. This contract is the boundary between what the portal can guarantee and what it delegates to the CRD target author.

**Monolith, not microservices.** The Web Application is intentionally a single deployable binary. The operational surface is kept small: one Deployment, one Service, no inter-service networking inside the portal boundary. The separation of concerns is internal (packages, not processes).

**Policy as data, not code.** The approval policy lives in `ResourceCatalogue` and is snapshotted into `ResourceRequest` at submission time. The Approval Controller is a pure state machine that never contains routing logic. Routing rules can be changed without redeploying the controller, and historical requests always reflect the policy that was in effect when they were submitted.

**Pre-resolved approver list.** The Web App translates a routing rule into a list of concrete identities at submission time. The controller sees only a flat list — no LDAP lookups, no group expansion at reconcile time. This keeps the controller fast, testable, and independent of directory service availability.

**Informer, not polling.** The Web App uses a informer to maintain a live cache of `ResourceRequest` and `ProvisionedResource` objects. Status updates appear in the UI within the informer's resync period, driven by Kubernetes watch events, with no per-request API calls.

**Three CRDs, all on the management cluster.** There is no portal-specific database. The management cluster's etcd is the authoritative store for all portal state. `ResourceRequest` and `ProvisionedResource` are controller-owned; `ResourceCatalogue` is admin-owned.

**Failure is a first-class state.** `failed` is a terminal phase with a structured `failureReason`. The controller retries with backoff before reaching it. Once in `failed`, the request is immutable — a new request must be submitted. This avoids ambiguous partial-apply states.
