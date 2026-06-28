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
        docs docs-html \
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

# ─── AsciiDoctor detection ────────────────────────────────────────────────────
#
# Resolution order (first match wins):
#   1. $$ASCIIDOCTOR_CMD  env var (e.g. "asciidoctor" or "bundle exec asciidoctor")
#   2. `asciidoctor`      binary on PATH  (zypper install asciidoctor / gem install asciidoctor)
#   3. Container          asciidoctor/docker-asciidoctor (pulled on demand via RUNTIME)
#
# Override with:
#   ASCIIDOCTOR_CMD="bundle exec asciidoctor" make docs-html
#   ASCIIDOCTOR_CMD="docker run --rm -v \$$(pwd):/work asciidoctor/docker-asciidoctor asciidoctor" make docs-html
#
# The HTML output lands in html/ — one file per .adoc source.
# The top-level resource_portal.adoc (which includes the others) is built as
# the main document; individual sub-documents are also built standalone.

# Source directory for .adoc files (relative to the Makefile)
ADOC_SRC     ?= .
# Destination for rendered HTML files
ADOC_DEST    ?= html
# Attributes passed to every asciidoctor invocation
ADOC_ATTRS   ?= -a toc -a toclevels=3 -a sectnums -a icons=font -a data-uri

ifdef ASCIIDOCTOR_CMD
  _ASCIIDOCTOR := $(ASCIIDOCTOR_CMD)
  _ADOC_CONTAINER :=
else ifneq ($(shell command -v asciidoctor 2>/dev/null),)
  _ASCIIDOCTOR := asciidoctor
  _ADOC_CONTAINER :=
else
  # Fallback: run the official Asciidoctor container.
  # The CWD is mounted at /documents (the image's default WORKDIR).
  _ASCIIDOCTOR := $(RUNTIME) run --rm \
    -v "$$(pwd):/documents:z" \
    asciidoctor/docker-asciidoctor asciidoctor
  _ADOC_CONTAINER := 1
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

# ─── AsciiDoc → HTML ──────────────────────────────────────────────────────────
#
# docs        alias for docs-html (room to add docs-pdf later)
# docs-html   render all .adoc files → exported/html/
#
# The main document (resource_portal.adoc) is built first; it pulls in the
# sub-documents via include directives, producing a single self-contained HTML.
# Each sub-document is then also rendered standalone so individual sections
# can be linked or previewed on their own.
#
# Images (SVG, PNG) are embedded as base64 data URIs (-a data-uri) so each
# HTML file is fully self-contained — no external image files required.
# imagesdir is always set to the absolute path of the source images/ directory
# so that relative image:: references resolve correctly before embedding.

ADOC_MAIN    ?= resource_portal.adoc
ADOC_STANDALONE ?= resource_portal_c4_context.adoc \
                   resource_portal_c4_container.adoc \
                   resource_portal_c4_component.adoc \
                   resource_portal_glossary.adoc \
                   makefile.adoc

docs: docs-html ## Render AsciiDoc sources → HTML (alias)

docs-html: ## Render .adoc files → exported/html/  (images embedded as data URIs)
	@echo ""
	@echo "  Engine   : $(_ASCIIDOCTOR)"
	@echo "  Source   : $(ADOC_SRC)/"
	@echo "  Output   : $(ADOC_DEST)/"
	@echo "  Images   : embedded as data URIs (-a data-uri)"
	@echo ""
	@mkdir -p "$(ADOC_DEST)"
	@absout=$$(pwd)/$(ADOC_DEST); \
	abssrc=$$(pwd)/$(ADOC_SRC); \
	echo "  [main]   $(ADOC_MAIN)"; \
	if [ -n "$(_ADOC_CONTAINER)" ]; then \
	  $(RUNTIME) run --rm \
	    -v "$$abssrc:/documents:z" \
	    asciidoctor/docker-asciidoctor asciidoctor \
	    $(ADOC_ATTRS) \
	    -a imagesdir=/documents/images \
	    -D /documents/$(ADOC_DEST) \
	    "$(ADOC_MAIN)"; \
	else \
	  $(_ASCIIDOCTOR) \
	    $(ADOC_ATTRS) \
	    -a imagesdir="$$abssrc/images" \
	    -D "$$absout" \
	    "$$abssrc/$(ADOC_MAIN)"; \
	fi
	@absout=$$(pwd)/$(ADOC_DEST); \
	abssrc=$$(pwd)/$(ADOC_SRC); \
	for adoc in $(ADOC_STANDALONE); do \
	  echo "  [doc]    $$adoc"; \
	  if [ -n "$(_ADOC_CONTAINER)" ]; then \
	    $(RUNTIME) run --rm \
	      -v "$$abssrc:/documents:z" \
	      asciidoctor/docker-asciidoctor asciidoctor \
	      $(ADOC_ATTRS) \
	      -a imagesdir=/documents/images \
	      -D /documents/$(ADOC_DEST) \
	      "$$adoc"; \
	  else \
	    $(_ASCIIDOCTOR) \
	      $(ADOC_ATTRS) \
	      -a imagesdir="$$abssrc/images" \
	      -D "$$absout" \
	      "$$abssrc/$$adoc"; \
	  fi; \
	done
	@echo ""
	@echo "  HTML files written to $(ADOC_DEST)/"
	@echo ""

# ─── Utility ──────────────────────────────────────────────────────────────────

clean: ## Remove all exported files (SVG, PNG, PlantUML, HTML, …)
	rm -rf exported/ html/
	@echo "exported/ and html/ directories removed."

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
