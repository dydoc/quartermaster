# Architecture

Architecture documentation for the project using [Structurizr](https://structurizr.com) and the C4 model.

## Layout

```
architecture/
├── docker-compose.yml          # Structurizr vNext (local)
├── Makefile                    # Entry point for all commands
├── .gitignore
├── export/
│   └── export.sh               # Multi-format export script
├── workspace/
│   ├── workspace.dsl           # <- SOURCE: C4 model in DSL
│   ├── workspace.json          # <- LAYOUT: written automatically by the UI (commit this!)
│   └── docs/
│       ├── README.md           # Textual documentation (imported via !docs)
│       └── decisions/          # Architecture Decision Records
│           └── 0001-*.md
└── exported/                   # Generated artefacts (do not commit)
    ├── png/                    # High-resolution PNG
    ├── svg/                    # SVG (ideal for AsciiDoc / Markdown)
    ├── plantuml/               # Standard PlantUML
    ├── plantuml-c4/            # PlantUML with C4 styles (visually closer to the UI)
    ├── mermaid/                # Mermaid (GitHub, GitLab, MkDocs)
    ├── dot/                    # Graphviz DOT
    ├── ilograph/               # Ilograph (interactive)
    ├── json/                   # Serialised workspace JSON
    └── static/                 # Navigable static site
```

## Prerequisites

- Docker **or** Podman — nothing else required at the OS level.

## Quick start

```bash
make up    # start Structurizr — runtime auto-detected
make open  # open http://127.0.0.1:8080
```

## Runtime detection

The Makefile and `export.sh` auto-detect the container runtime (Docker preferred,
Podman as fallback) and the compose command. You can always pin them explicitly:

```bash
CONTAINER_RUNTIME=podman make up
CONTAINER_RUNTIME=docker make export
COMPOSE_CMD="docker-compose" make up   # pin a specific compose binary
```

Or export for the whole shell session:

```bash
export CONTAINER_RUNTIME=podman
make up
make export
```

### Compose resolution order (Podman)

The following are tried in order; the first one found is used:

1. `$COMPOSE_CMD` env var — explicit override, always honoured
2. `docker compose` plugin — works when `DOCKER_HOST` points to the Podman socket
3. `docker-compose` standalone binary — same socket approach
4. `podman compose` thin wrapper — requires an external provider (Podman ≥ 4.7)
5. `podman-compose` Python package

### Podman one-time setup (openSUSE and other distros without podman-compose)

The recommended approach is to expose the rootless Podman socket and point
`DOCKER_HOST` at it, so that `docker-compose` works without any wrapper:

```bash
# 1. Enable the user-level socket (survives reboots)
systemctl --user enable --now podman.socket

# 2. Add to ~/.bashrc (or ~/.profile)
echo 'export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock' >> ~/.bashrc
source ~/.bashrc

# 3. Install docker-compose (openSUSE)
sudo zypper install docker-compose

# 4. Verify — should show containers managed by Podman
docker-compose version
```

There is also a convenience target that prints these steps:

```bash
make podman-setup
```

After the one-time setup, `make up` and `make export` work exactly like Docker.

## Typical workflow

```
1.  Edit  workspace/workspace.dsl  in your editor
          (VS Code + Structurizr extension recommended)

2.  Refresh  http://127.0.0.1:8080  -> changes appear immediately

3.  Adjust the layout in the UI by dragging elements
          -> Structurizr saves positions automatically to workspace.json

4.  make export   -> produces all formats under exported/

5.  git add workspace/workspace.dsl workspace/workspace.json
    git commit -m "update architecture"
```

## Export formats

| Format | Command | Notes |
|--------|---------|-------|
| PNG | `make export-png` | Requires `-playwright` tag; UI-faithful |
| SVG | `make export-svg` | Requires `-playwright` tag; ideal for docs |
| PlantUML | `make export-plantuml` | Standard + C4 variant |
| Mermaid | `make export-mermaid` | Native GitHub, GitLab, MkDocs support |
| DOT | `make export-text` | Graphviz, precise layout control |
| Ilograph | `make export-text` | Interactive visualisation |
| JSON | `make export-text` | Full serialised workspace |
| Static | `make export-static` | Offline-navigable HTML site |
| **All** | `make export` | Runs all of the above |

## Using diagrams in AsciiDoc

```asciidoc
// After make export-svg:
image::../architecture/exported/svg/structurizr-SystemContext.svg[System Context,opts=inline]
image::../architecture/exported/svg/structurizr-Containers.svg[Containers,opts=inline]
```

## Using diagrams in Markdown

```markdown
<!-- After make export-svg: -->
![System Context](../architecture/exported/svg/structurizr-SystemContext.svg)
```

## What to commit

| File | Role | Commit? |
|------|------|---------|
| `workspace.dsl` | Model: elements, relationships, views | ✅ Always |
| `workspace.json` | Diagram layout (element positions) | ✅ Always |
| `exported/*` | Generated artefacts | ❌ Never — use `make export` |

`workspace.json` does not contain the model (that lives in the DSL) — it only stores
the X/Y coordinates of elements in the UI. Without it, every restart falls back to
autolayout and all manual positioning is lost.

## Updating the container image

```bash
# Check the latest tag at https://hub.docker.com/r/structurizr/structurizr/tags
# Update the tag in docker-compose.yml, then:
make down
# edit docker-compose.yml with the new tag
make up
```

## Available commands

```
make up              Start Structurizr
make down            Stop Structurizr
make open            Open http://127.0.0.1:8080
make export          Export all formats
make export-svg      SVG only
make export-png      PNG only
make export-text     PlantUML + Mermaid + DOT + Ilograph + JSON
make export-static   Static site
make export-plantuml PlantUML only
make export-mermaid  Mermaid only
make logs            Follow container logs
make status          Container status
make clean           Remove exported/
make podman-setup    Print Podman one-time setup instructions (openSUSE / rootless)
```
