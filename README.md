# Resource Portal — Architecture Documentation

This repository contains the architecture design documentation for the **Resource Portal**: a self-service portal that lets teams request and manage infrastructure resources (e.g. namespaces, databases, storage) on Rancher-managed Kubernetes clusters, with a built-in multi-stage approval workflow.

---

## What is documented

The documentation follows the [C4 model](https://c4model.com/) — a hierarchical approach that describes the system at three increasing levels of detail:

| Level | Document | What it answers |
|---|---|---|
| **Context** | `design/resource_portal_c4_context.adoc` | Who uses the system and what external systems does it depend on? |
| **Container** | `design/resource_portal_c4_container.adoc` | What are the deployable components (services, CRDs) and how do they communicate? |
| **Component** | `design/resource_portal_c4_component.adoc` | What are the internal modules inside each container and how do they interact? |
| **Glossary** | `design/resource_portal_glossary.adoc` | Definitions for all abbreviated terms and domain-specific names used across the docs. |

All four documents are also combined into a single file: `design/resource_portal.adoc`.

## How to read the documentation

### Option 1 — Read the pre-rendered HTML (quickest)

Open any file in the `design/html/` directory in your browser.

- `design/html/resource_portal.html` — full combined document (all levels + glossary)
- Individual section files are also available (`design/html/resource_portal_c4_container.html`, etc.)

All images are embedded in the HTML — no external files needed.

### Option 2 — Browse the C4 diagrams interactively

Start the Structurizr local server and open the diagram browser:

```sh
cd design
make up
make open   # opens http://127.0.0.1:8080 in your browser
```

The Structurizr UI lets you zoom into and navigate the C4 Context and Container diagrams and shows relationship descriptions on hover.

### Option 3 — Read the AsciiDoc sources

The `.adoc` source files are plain text and readable as-is. Start with `design/resource_portal.adoc` for the full picture, or open any individual document directly.

---

## Rebuilding the HTML (contributors)

All `make` targets must be run from the `design/` directory.

If you edit the `.adoc` sources or diagrams, regenerate the HTML with:

```sh
cd design

# After editing PlantUML sequence/state diagrams (design/plantuml/*.puml)
make plantuml-svg && make docs-html

# After editing the C4 model (design/workspace/workspace.dsl)
# Requires Structurizr running: make up
make export-svg && make images-sync && make docs-html
```

Run `make help` from `design/` for the full list of available targets.

> **Prerequisites:** Docker or Podman. All other tools (Structurizr, PlantUML, AsciiDoctor) run as containers automatically if not installed locally.
