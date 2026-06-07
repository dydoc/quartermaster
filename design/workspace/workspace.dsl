workspace "Resource Portal" "C4 diagrams — Resource Portal v9. Self-service portal for infrastructure resources on Rancher-managed Kubernetes clusters. User identity governs management-cluster operations; the Approval Controller acts under its own service account on target clusters." {

    model {

        # ── Human actors ──────────────────────────────────────────────────────
        endUser = person "End User" "Requests and monitors infrastructure resources via the portal." {
            tags "Actor"
        }

        approver = person "Approver" "Reviews and approves resource requests before provisioning." {
            tags "Actor"
        }

        platformAdmin = person "Platform Admin" "Configures available resource types, quotas, and approval policies." {
            tags "Actor"
        }

        # ── External systems ──────────────────────────────────────────────────
        idp = softwareSystem "Identity Provider" "Central authentication service (Keycloak / LDAP / SSO). Shared by the portal and all downstream clusters." {
            tags "External"
        }

        # Rancher acts as an authn/RBAC proxy; it does not act autonomously on clusters.
        # The downstream clusters host the CRD target instances and controllers.
        platformInfra = softwareSystem "Platform Infrastructure" "Rancher (authn/RBAC proxy) + Rancher-managed K8s clusters. The Approval Controller applies CRD target instances under its own service account; end users hold no permissions on those types." {
            tags "PlatformInternal"
        }

        # ── System in scope ───────────────────────────────────────────────────
        resourcePortal = softwareSystem "Resource Portal" "Self-service portal for requesting and managing infrastructure resources on Kubernetes clusters." {
            tags "InScope"

            # ── Containers ───────────────────────────────────────────────────

            webApp = container "Web Application" "Server-side rendered monolith. Handles HTTP sessions, renders UI, resolves approver list at submission time, and maintains a local informer cache for live resource state." {
                tags "Container WebApp"
                technology "HTTPS"
            }

            approvalController = container "Approval Controller" "Kubernetes controller (controller-runtime). Drives the ResourceRequest state machine; applies CRD target instances on downstream clusters under its own service account via SSA. The Health Observer monitors CRD target instance health and restores out-of-band deletions. Derived object drift is corrected by the CRD target controller." {
                tags "Container Controller"
                technology "Go, controller-runtime"
            }

            resourceRequestCRD = container "ResourceRequest CRD" "Full lifecycle of a resource request: pending → approved/rejected → provisioning → provisioned/failed. Carries embedded approval policy, pre-resolved approver list, and previousParameters for update rollback. Critical spec fields are immutable via CEL rules." {
                tags "Container CRD"
                technology "Kubernetes CRD (cluster: management)"
            }

            provisionedResourceCRD = container "ProvisionedResource CRD" "Authoritative record of a confirmed-operational provisioned resource. Written only after Ready confirmation on the target cluster. Carries a deprovisioning finalizer; read by the Web App informer for live status display." {
                tags "Container CRD"
                technology "Kubernetes CRD (cluster: management)"
            }

            resourceCatalogueCRD = container "ResourceCatalogue CRD" "Defines available resource types, quota limits, and approval routing rules. Managed by Platform Admins; read by the Web App at submission time." {
                tags "Container CRD"
                technology "Kubernetes CRD (cluster: management)"
            }

            mailRelay = container "Mail Relay" "SMTP relay. Delivers state-change notifications to requesters on provisioned and failed transitions." {
                tags "Container External"
                technology "SMTP"
            }
        }

        # ── Relationships — System Context ────────────────────────────────────

        endUser       -> resourcePortal "Requests resources and monitors status"
        approver      -> resourcePortal "Reviews and approves requests"
        platformAdmin -> resourcePortal "Configures policies and resource catalogue"

        resourcePortal -> idp           "Authenticates users via OIDC"
        platformInfra  -> idp           "Verifies user tokens via OIDC"

        # Web App authenticates as the logged-in user (via Rancher proxy).
        # Approval Controller authenticates as its own service account.
        resourcePortal -> platformInfra "Web App reads cluster state as user; Controller applies CRD target instances as service account"

        # ── Relationships — Container level ───────────────────────────────────

        endUser       -> webApp "Browses catalogue, submits requests, monitors status [HTTPS]"
        approver      -> webApp "Reviews and approves/rejects requests [HTTPS]"
        platformAdmin -> webApp "Manages resource catalogue and policies [HTTPS]"

        webApp -> idp                 "Authenticates session via OIDC"
        webApp -> resourceRequestCRD  "Creates ResourceRequest; records approver decisions"
        webApp -> resourceCatalogueCRD "Reads resource types and approval policy at submission time"
        webApp -> provisionedResourceCRD "Reads live state via informer cache (no polling)"

        approvalController -> resourceRequestCRD     "Watches events; drives phase transitions"
        approvalController -> provisionedResourceCRD "Creates/updates on confirmed provisioning; manages deprovisioning finalizer"
        approvalController -> platformInfra          "Applies/deletes CRD target instances via SSA; Health Observer reads instance status read-only"
        approvalController -> mailRelay              "Sends notification on provisioned / failed"
    }

    views {

        # ── C4 Context ────────────────────────────────────────────────────────
        systemContext resourcePortal "C4Context_ResourcePortal" {
            title "Resource Portal — System Context"
            description "Shows the Resource Portal and its relationships with users, the Identity Provider, and the Platform Infrastructure (Rancher + downstream Kubernetes clusters)."
            include *
        }

        # ── C4 Container ──────────────────────────────────────────────────────
        container resourcePortal "C4Container_ResourcePortal" {
            title "Resource Portal — Containers"
            description "Internal structure of the Resource Portal deployed on the Rancher management cluster. The component-level detail of the Web Application and Approval Controller is documented via PlantUML sequence and state diagrams."
            include *
        }

        styles {

            # ── People ────────────────────────────────────────────────────────
            element "Actor" {
                shape Person
                background #E1F5EE
                color #085041
                stroke #0F6E56
            }

            # ── Software Systems ──────────────────────────────────────────────
            element "InScope" {
                background #EEEDFE
                color #3C3489
                stroke #534AB7
            }
            element "PlatformInternal" {
                width 380
                height 470
                background #FFF3CD
                color #7A4F00
                stroke #B07D00
            }
            element "External" {
                width 280
                height 400
                background #F1EFE8
                color #44443F
                stroke #5F5E5A
            }

            # ── Containers ────────────────────────────────────────────────────
            element "Container WebApp" {
                shape RoundedBox
                background #EEEDFE
                color #3C3489
                stroke #534AB7
                width 450
                height 350
            }
            element "Container Controller" {
                background #e6b518
                color #7A4F00
                stroke #B07D00
                width 500
                height 550
            }
            element "Container CRD" {
                background #E8F4FD
                color #0B4F6C
                stroke #1A7BB9
                width 500
                height 400
            }
            element "Container External" {
                shape Component
                background #F1EFE8
                color #44443F
                stroke #5F5E5A
                width 420
                height 300
            }

            # ── Relationships ─────────────────────────────────────────────────
            relationship "Relationship" {
                color #737266
                style dashed
                thickness 2
            }
        }
    }
}
