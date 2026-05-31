workspace "Resource Portal" "C4 Context diagram — Resource Portal v6. The portal provides self-service access to infrastructure resources on Rancher-managed Kubernetes clusters. All resource types are implemented as CRDs. User identity is propagated end-to-end through Rancher to each downstream cluster." {

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
        idp = softwareSystem "Identity Provider" "Central authentication service (Keycloak / LDAP / SSO). Shared by the portal and all downstream clusters — user identity is consistent end-to-end." {
            tags "External"
        }

        # Rancher and the downstream clusters are collapsed into a single boundary:
        # Rancher acts as an authn/RBAC proxy; it does not act autonomously on clusters.
        # The downstream clusters host the CRDs and controllers that reconcile resource state.
        platformInfra = softwareSystem "Platform Infrastructure" "Rancher (authn/RBAC proxy) + Rancher-managed K8s clusters. User identity propagated end-to-end. Each resource type backed by a CRD and a reconciling controller." {
            tags "PlatformInternal"
        }

        # ── System in scope ───────────────────────────────────────────────────
        resourcePortal = softwareSystem "Resource Portal" "Self-service portal for requesting and managing infrastructure resources. Translates approved requests into CRD manifests applied on the target clusters." {
            tags "InScope"
        }

        # ── Relationships ─────────────────────────────────────────────────────

        # Actors → Resource Portal
        endUser       -> resourcePortal "Requests resources and monitors status"
        approver      -> resourcePortal "Reviews and approves requests"
        platformAdmin -> resourcePortal "Configures policies and resource catalogue"

        # Resource Portal → Identity Provider
        resourcePortal -> idp "Authenticates users via OIDC"

        # Resource Portal → Platform Infrastructure
        resourcePortal -> platformInfra "Applies CRDs and reads resource state (user identity end-to-end)"
        platformInfra -> idp "Verifies user tokens via OIDC"
    }

    views {

        systemContext resourcePortal "C4Context_ResourcePortal" {
            title "Resource Portal — System Context"
            description "Shows the Resource Portal and its relationships with users, the Identity Provider, and the Platform Infrastructure (Rancher + downstream Kubernetes clusters)."
            include *
            autoLayout
        }

        styles {
            element "Actor" {
                shape Person
                background #E1F5EE
                color #085041
                stroke #0F6E56
            }
            element "InScope" {

                background #EEEDFE
                color #3C3489
                stroke #534AB7
            }
            element "PlatformInternal" {
                width 380
                height 400
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
            relationship "Relationship" {
                color #737266
                style dashed
                thickness 2
            }
        }
    }
}
