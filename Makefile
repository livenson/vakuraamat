# Vakuraamat build helpers. Run from the repo root on macOS.
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
BLENDER ?= /Applications/Blender.app/Contents/MacOS/Blender
# The active site pack (sites/<SITE>/site.json) names its terrain tile and the tile centre (EPSG:3301).
SITE ?= palupera
TILE ?= $(shell python3 -c "import json;print(json.load(open('sites/$(SITE)/site.json'))['terrain']['tile'])")
CENTER ?= $(shell python3 -c "import json;print(*json.load(open('sites/$(SITE)/site.json'))['terrain']['center'])")

.PHONY: help setup import tile scatter trees props ink test lint export clean-generated site era-maps features scenes validate tile-service world-service buildings real-trees dev-watch parcels roads market tenants module server town

help:
	@echo "make setup            install tools (Homebrew: godot, blender, gdal, git-lfs; npm for ink), pull LFS files, first Godot import"
	@echo "make tile             fetch Maa-amet data for SITE (tile/centre from sites/$(SITE)/site.json), import into Terrain3D, scatter vegetation (regenerates assets/terrain/$(TILE)/data)"
	@echo "make scatter          re-scatter vegetation only"
	@echo "make trees            regenerate tree models, prepared meshes and impostor atlases (needs a window for the bake)"
	@echo "make props            regenerate Blender props (oak, boundary stone, buildings, figures)"
	@echo "make ink              compile sites/*/narrative/*.ink"
	@echo "make test             run the headless test suite"
	@echo "make lint             gdlint, ruff, shellcheck (same as the GitHub workflow; needs uv and shellcheck)"
	@echo "make export           export the macOS build to build/Vakuraamat.zip"
	@echo "make site SITE=x NAME=\"X\" CENTER=\"E N\"  scaffold a new location/story pack under sites/x (EPSG:3301 centre)"
	@echo "make era-maps         fetch the historical ground maps (WMS) named in sites/$(SITE)/site.json and relink the eras"
	@echo "make features         derive sites/$(SITE)/buildings_*.json and water_*.json from the tile (author edits afterwards)"
	@echo "make scenes           regenerate sites/$(SITE)/scenes/*.tscn from scenes.json + layout.json"
	@echo "make validate         check every site pack for broken references (no Godot needed)"
	@echo "make tenants          match e-Business Register companies to the tile's parcels and buildings into sites/$(SITE)/tenants.json"
	@echo "make module           build the town ledger module (server/vakuraamat, Rust -> wasm; needs rustup with the wasm32 target)"
	@echo "make server           run a local SpacetimeDB (spacetime start, 127.0.0.1:3300, log under the user dir)"
	@echo "make town             publish the module as SITE's town (name from tools/town_admin.py) to SERVER and seed it from the pack"
	@echo "make market           derive sites/$(SITE)/market.json (land value medians per purpose; XLSX=<maa-amet export> joins transaction statistics)"

setup:
	brew list --cask godot >/dev/null 2>&1 || brew install --cask godot
	brew list --cask blender >/dev/null 2>&1 || brew install --cask blender
	brew list gdal >/dev/null 2>&1 || brew install gdal
	brew list git-lfs >/dev/null 2>&1 || brew install git-lfs
	git lfs install && git lfs pull
	cd tools/ink && npm install
	xattr -dr com.apple.quarantine addons/terrain_3d 2>/dev/null || true
	$(MAKE) ink
	$(MAKE) import
	@test -f assets/terrain/$(TILE)/data/terrain3d_00_00.res || echo ">> terrain region data is not in git: run 'make tile' (network, ~10 min)"

import:
	$(GODOT) --headless --path . --import >/dev/null 2>&1 || true

tile:
	python3 tools/pipeline/fetch_tile.py --site $(SITE)
	python3 tools/new_site.py --id $(SITE) --relink-era-maps
	$(MAKE) real-trees
	$(MAKE) import
	$(GODOT) --headless --path . -s res://tools/godot/import_terrain.gd -- --site=$(SITE) --tile=$(TILE)
	$(MAKE) scatter
	@[ -s sites/$(SITE)/buildings_2026.json ] && [ "$$(cat sites/$(SITE)/buildings_2026.json)" != "[]" ] || $(MAKE) features
	@[ -s sites/$(SITE)/buildings.json ] || $(MAKE) buildings
	@[ -s sites/$(SITE)/parcels.json ] || $(MAKE) parcels
	@[ -s sites/$(SITE)/roads.json ] || $(MAKE) roads
	@[ -s sites/$(SITE)/market.json ] || $(MAKE) market
	@[ -s sites/$(SITE)/tenants.json ] || $(MAKE) tenants
	$(MAKE) scenes
	python3 tools/validate_site.py --site $(SITE)

site:
	@test -n "$(CENTER)" || (echo 'usage: make site SITE=id NAME="Display name" CENTER="easting northing" [ERAS=1798,1938,2026]'; exit 1)
	python3 tools/new_site.py --id $(SITE) --name "$(or $(NAME),$(SITE))" --center $(CENTER) --eras $(or $(ERAS),1798,1938,2026)
	$(MAKE) ink
	$(MAKE) scenes
	$(MAKE) import
	python3 tools/validate_site.py --site $(SITE)

era-maps:
	python3 tools/pipeline/fetch_tile.py --site $(SITE) --only-era-maps
	python3 tools/new_site.py --id $(SITE) --relink-era-maps
	$(MAKE) import

features:
	python3 tools/pipeline/extract_features.py --site $(SITE)

buildings:
	python3 tools/pipeline/fetch_buildings.py --site $(SITE)

real-trees:
	python3 tools/pipeline/fetch_trees.py --site $(SITE)

parcels:
	python3 tools/pipeline/fetch_parcels.py --site $(SITE)

tenants:
	python3 tools/pipeline/fetch_tenants.py --site $(SITE) --stats

# SpacetimeDB toolchain: the CLI installs to ~/.local/bin, rustup (brew) to /opt/homebrew/opt/rustup/bin.
STDB_PATH := /opt/homebrew/opt/rustup/bin:$(HOME)/.cargo/bin:$(HOME)/.local/bin:$(PATH)
SERVER ?= http://127.0.0.1:3300
TOWN ?= $(shell python3 tools/town_admin.py name --site $(SITE))
USERDIR := $(HOME)/Library/Application Support/Godot/app_userdata/Vakuraamat

module:
	cd server/vakuraamat && PATH="$(STDB_PATH)" cargo test --quiet && PATH="$(STDB_PATH)" spacetime build

server:
	@mkdir -p "$(USERDIR)/logs"
	@echo ">> SpacetimeDB on $(SERVER), log $(USERDIR)/logs/spacetime.log (Ctrl-C stops it)"
	PATH="$(STDB_PATH)" spacetime start --listen-addr 127.0.0.1:3300 2>&1 | tee "$(USERDIR)/logs/spacetime.log"

town: module
	PATH="$(STDB_PATH)" spacetime publish -s $(SERVER) -p server/vakuraamat -y $(TOWN)
	PATH="$(STDB_PATH)" python3 tools/town_admin.py seed --site $(SITE) --server $(SERVER) --db $(TOWN) $(if $(DEBUG),--debug)

market:
	python3 tools/pipeline/market.py --site $(SITE) $(if $(XLSX),--xlsx $(XLSX))

roads:
	python3 tools/pipeline/fetch_roads.py --site $(SITE)

scenes:
	python3 tools/gen_era_scenes.py --site $(SITE)

validate:
	python3 tools/validate_site.py --all

scatter:
	$(GODOT) --headless --path . -s res://tools/godot/scatter_vegetation.gd -- --site=$(SITE) --tile=$(TILE)
	$(MAKE) import

trees:
	$(BLENDER) -b -P tools/blender/make_trees.py -- assets/models/trees
	$(MAKE) import
	$(GODOT) --headless --path . -s res://tools/godot/prepare_trees.gd
	$(MAKE) import
	$(GODOT) --path . --resolution 1200x800 res://tools/godot/bake_impostors.tscn
	$(MAKE) import

props:
	$(BLENDER) -b -P tools/blender/make_oak.py -- assets/models/props/oak.glb
	$(BLENDER) -b -P tools/blender/make_boundary_stone.py -- assets/models/props/boundary_stone.glb
	$(BLENDER) -b -P tools/blender/make_buildings.py -- assets/models/buildings
	$(BLENDER) -b -P tools/blender/make_figure.py -- assets/models/figures
	$(GODOT) --headless --path . -s res://tools/godot/prepare_vegetation.gd
	$(MAKE) import

ink:
	cd tools/ink && npm run compile

test:
	@python3 tools/validate_site.py --all | grep -E "OK|FAILED"
	@for t in boot_test site_test userpack_test friends_test devchannel_test traffic_test streaming_test playthrough_test story_test farming_test hunting_test economy_test ledger_test; do \
	  printf "%-18s " $$t; timeout 180 $(GODOT) --headless --path . res://tools/godot/$$t.tscn -- --site=palupera 2>&1 | grep -E "PASSED|FAILED" | head -1; if [ "$${PIPESTATUS[0]}" = 124 ]; then echo "TIMEOUT (stuck after 180 s)"; fi; done

lint:
	git ls-files '*.gd' | grep -v '^addons/\|^spacetime_bindings/' | xargs uvx --python 3.12 --from gdtoolkit==4.5.0 gdlint
	uvx ruff@0.16.6 check tools
	git ls-files '*.sh' | xargs shellcheck

export:
	mkdir -p build && $(GODOT) --headless --path . --export-release "macOS" build/Vakuraamat.zip

clean-generated:
	rm -rf assets/terrain/$(TILE)/data assets/models/trees/*_impostor.png assets/models/trees/*_mesh.res

play:
	tools/play.sh $(ARGS)

tile-service:
	python3 tools/tile_service.py --port 8765

world-service:
	python3 tools/world_service.py --port 8766

dev-watch:
	python3 tools/dev.py watch
