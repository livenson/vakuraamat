# Vakuraamat build helpers. Run from the repo root on macOS.
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
BLENDER ?= /Applications/Blender.app/Contents/MacOS/Blender
TILE ?= palupera
CENTER ?= 637548 6444029

.PHONY: help setup import tile scatter trees props ink test export clean-generated

help:
	@echo "make setup            install tools (Homebrew: godot, blender, gdal, git-lfs; npm for ink), pull LFS files, first Godot import"
	@echo "make tile             fetch Maa-amet data for TILE/CENTER, import into Terrain3D, scatter vegetation (regenerates assets/terrain/$(TILE)/data)"
	@echo "make scatter          re-scatter vegetation only"
	@echo "make trees            regenerate tree models, prepared meshes and impostor atlases (needs a window for the bake)"
	@echo "make props            regenerate Blender props (oak, boundary stone, buildings, figures)"
	@echo "make ink              compile assets/narrative/*.ink"
	@echo "make test             run the headless test suite"
	@echo "make export           export the macOS build to build/Vakuraamat.zip"

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
	python3 tools/pipeline/fetch_tile.py --name $(TILE) --center $(CENTER) --size 1024
	$(MAKE) import
	$(GODOT) --headless --path . -s res://tools/godot/import_terrain.gd -- --tile=$(TILE)
	$(MAKE) scatter

scatter:
	$(GODOT) --headless --path . -s res://tools/godot/scatter_vegetation.gd -- --tile=$(TILE)
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
	@for t in boot_test playthrough_test farming_test hunting_test economy_test; do \
	  printf "%-18s " $$t; $(GODOT) --headless --path . res://tools/godot/$$t.tscn 2>&1 | grep -E "PASSED|FAILED" | head -1; done

export:
	mkdir -p build && $(GODOT) --headless --path . --export-release "macOS" build/Vakuraamat.zip

clean-generated:
	rm -rf assets/terrain/$(TILE)/data assets/models/trees/*_impostor.png assets/models/trees/*_mesh.res
