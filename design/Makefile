# Makefile — Structurizr architecture workflow
#
# Works with Docker and Podman (including rootless Podman on openSUSE).
#
# Runtime is auto-detected; override with env vars:
#   CONTAINER_RUNTIME=podman make up
#   CONTAINER_RUNTIME=docker make up
#   COMPOSE_CMD="docker-compose" make up
#
# Podman compose resolution order (first match wins):
#   1. $$COMPOSE_CMD env var
#   2. `docker compose`  plugin  (works when DOCKER_HOST -> Podman socket)
#   3. `docker-compose`  standalone
#   4. `podman compose`  thin wrapper  (Podman >= 4.7, needs external provider)
#   5. `podman-compose`  Python package
#
# On openSUSE with Podman the recommended one-time setup is:
#   make podman-setup    <- run this once, then restart your shell

.PHONY: up down export export-svg export-png export-text export-static \
        export-plantuml export-mermaid export-plantuml-svg plantuml-svg \
        open status logs clean podman-setup help

SHELL := /bin/bash

# ─── Runtime detection ────────────────────────────────────────────────────────

ifdef CONTAINER_RUNTIME
  RUNTIME := $(CONTAINER_RUNTIME)
else
  RUNTIME := $(shell command -v docker >/dev/null 2>&1 && echo docker || echo podman)
endif

# Compose detection — mirrors the logic in export.sh
ifdef COMPOSE_CMD
  COMPOSE := $(COMPOSE_CMD)
else ifeq ($(RUNTIME),docker)
  COMPOSE := $(shell docker compose version >/dev/null 2>&1 && echo "docker compose" || \
             command -v docker-compose >/dev/null 2>&1 && echo "docker-compose" || \
             echo "")
else
  # Podman: prefer docker compose via socket, then fallbacks
  COMPOSE := $(shell \
    (command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose") || \
    (command -v docker-compose >/dev/null 2>&1 && echo "docker-compose") || \
    (command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1 && echo "podman compose") || \
    (command -v podman-compose >/dev/null 2>&1 && echo "podman-compose") || \
    echo "")
endif

export CONTAINER_RUNTIME := $(RUNTIME)
export COMPOSE_CMD        := $(COMPOSE)

# ─── PlantUML detection ───────────────────────────────────────────────────────
#
# Resolution order (first match wins):
#   1. $$PLANTUML_CMD  env var (e.g. "plantuml" or "java -jar /opt/plantuml.jar")
#   2. `plantuml`      binary on PATH  (zypper install plantuml)
#   3. `java -jar`     with PLANTUML_JAR env var pointing to the .jar
#   4. Container       plantuml/plantuml (pulled on demand via RUNTIME)
#
# Override with:
#   PLANTUML_CMD="java -jar /opt/plantuml.jar" make plantuml-svg
#   PLANTUML_JAR=/opt/plantuml.jar make plantuml-svg
#   PLANTUML_CMD="docker run --rm -v \$$(pwd):/work plantuml/plantuml" make plantuml-svg

PLANTUML_JAR  ?=
# Directory containing .puml source files (versioned in the repo)
PLANTUML_SRC  ?= plantuml
PLANTUML_DEST ?= exported/svg-plantuml

ifdef PLANTUML_CMD
  _PLANTUML := $(PLANTUML_CMD)
else ifneq ($(shell command -v plantuml 2>/dev/null),)
  _PLANTUML := plantuml
else ifneq ($(PLANTUML_JAR),)
  _PLANTUML := java -jar $(PLANTUML_JAR)
else
  # Fallback: run the official PlantUML container via the detected runtime.
  # Files are mounted read-write so the container can write SVGs alongside the .puml sources.
  _PLANTUML := $(RUNTIME) run --rm -v "$$(pwd)/$(PLANTUML_SRC):/work" -w /work plantuml/plantuml
  _PLANTUML_CONTAINER := 1
endif

# ─── Helpers ──────────────────────────────────────────────────────────────────

define check_compose
	@if [[ -z "$(COMPOSE)" ]]; then \
	  echo ""; \
	  echo "  ERROR: no compose tool found for runtime '$(RUNTIME)'."; \
	  echo ""; \
	  echo "  On openSUSE with Podman, run once:"; \
	  echo "    make podman-setup"; \
	  echo ""; \
	  exit 1; \
	fi
endef

# ─── Podman one-time setup (openSUSE) ────────────────────────────────────────

podman-setup: ## (openSUSE/Podman) Enable the user socket and print shell config
	@echo ""
	@echo "  Enabling rootless Podman socket..."
	systemctl --user enable --now podman.socket
	@echo ""
	@echo "  Add this line to your ~/.bashrc (or ~/.profile):"
	@echo ""
	@echo '    export DOCKER_HOST=unix://$$XDG_RUNTIME_DIR/podman/podman.sock'
	@echo ""
	@echo "  Then install docker-compose if not already present:"
	@echo "    sudo zypper install docker-compose"
	@echo ""
	@echo "  Or the Python alternative:"
	@echo "    pip install --user podman-compose"
	@echo ""
	@echo "  Restart your shell and run 'make up'."
	@echo ""

# ─── Container ────────────────────────────────────────────────────────────────

up: ## Start Structurizr in the background
	$(call check_compose)
	@echo "  Runtime: $(RUNTIME)  Compose: $(COMPOSE)"
	$(COMPOSE) up -d
	@echo ""
	@echo "  Structurizr running at -> http://127.0.0.1:8080"
	@echo ""
	@echo "  Workflow:"
	@echo "    1. Edit workspace/workspace.dsl in your editor"
	@echo "    2. Refresh http://127.0.0.1:8080 to see changes"
	@echo "    3. Adjust layout in the UI (saved automatically to workspace/workspace.json)"
	@echo "    4. make export  to produce all output formats"
	@echo ""

down: ## Stop Structurizr
	$(call check_compose)
	$(COMPOSE) down

logs: ## Follow container logs
	$(call check_compose)
	$(COMPOSE) logs -f structurizr

status: ## Show container status
	$(call check_compose)
	$(COMPOSE) ps

open: ## Open the UI in the browser
	@which xdg-open >/dev/null 2>&1 && xdg-open http://127.0.0.1:8080 || \
	 which open      >/dev/null 2>&1 && open      http://127.0.0.1:8080 || \
	 echo "Open manually: http://127.0.0.1:8080"

# ─── Export ───────────────────────────────────────────────────────────────────

export: ## Export ALL formats (PNG, SVG, PlantUML, Mermaid, DOT, Ilograph, JSON, Static)
	@bash export/export.sh all

export-svg: ## Export SVG (UI-faithful, requires -playwright tag)
	@bash export/export.sh svg

export-png: ## Export PNG (UI-faithful, requires -playwright tag)
	@bash export/export.sh png

export-text: ## Export text formats (PlantUML, Mermaid, DOT, Ilograph, JSON)
	@bash export/export.sh text

export-static: ## Export navigable static site
	@bash export/export.sh static

export-plantuml: ## Export PlantUML only (C4 style)
	@bash export/export.sh plantuml

export-mermaid: ## Export Mermaid only (for GitHub / GitLab / MkDocs)
	@bash export/export.sh mermaid

plantuml-svg: ## Render exported .puml files → SVG  (uses plantuml binary, JAR, or container)
	@if [ ! -d "$(PLANTUML_SRC)" ]; then \
	  echo ""; \
	  echo "  ERROR: $(PLANTUML_SRC)/ not found."; \
	  echo "  Run 'make export-plantuml' first to generate the .puml sources."; \
	  echo ""; \
	  exit 1; \
	fi
	@puml_files=$$(find "$(PLANTUML_SRC)" -maxdepth 1 -name "*.puml"); \
	puml_count=$$(echo "$$puml_files" | grep -c '.puml' || true); \
	if [ -z "$$puml_files" ]; then \
	  echo "  No .puml files found in $(PLANTUML_SRC)/ — nothing to render."; \
	  exit 0; \
	fi; \
	mkdir -p "$(PLANTUML_DEST)"; \
	echo ""; \
	echo "  Rendering $$puml_count .puml file(s) → SVG"; \
	echo "  Source : $(PLANTUML_SRC)/"; \
	echo "  Output : $(PLANTUML_DEST)/"; \
	echo "  Engine : $(_PLANTUML)"; \
	echo ""; \
	absdest=$$(pwd)/$(PLANTUML_DEST); \
	abssrc=$$(pwd)/$(PLANTUML_SRC); \
	$(RUNTIME) run --rm \
	  -v "$$abssrc:/work:z" \
	  -v "$$absdest:/out:z" \
	  plantuml/plantuml \
	  -tsvg -o /out "/work"; \
	echo ""; \
	echo "  SVGs written to $(PLANTUML_DEST)/"; \
	echo ""

export-plantuml-svg: ## Export PlantUML sources then render them to SVG  (export-plantuml + plantuml-svg)
	@$(MAKE) export-plantuml
	@$(MAKE) plantuml-svg

# ─── Utility ──────────────────────────────────────────────────────────────────

clean: ## Remove all exported files
	rm -rf exported/
	@echo "exported/ directory removed."

help: ## Show this help
	@echo ""
	@echo "  Runtime detected : $(RUNTIME)"
	@echo "  Compose detected : $(if $(COMPOSE),$(COMPOSE),(none — run 'make podman-setup' or set COMPOSE_CMD))"
	@echo "  Override with    : CONTAINER_RUNTIME=podman make <target>"
	@echo "                     COMPOSE_CMD='podman-compose' make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
