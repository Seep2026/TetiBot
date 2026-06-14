USAGI_BIN ?= ./engine/usagi/target/release/usagi
PET_APP_ZIP := build/Teti-macos.zip
PET_APP_DIR := build/Teti.app

.PHONY: assets-master-128 check-aseprite-env pet-run pet-prototype pet-app pet-app-open

assets-master-128:
	./tools/asset-build/build_master_128.sh

check-aseprite-env:
	./tools/asset-build/check_aseprite_env.sh

pet-run:
	$(USAGI_BIN) run pet-runtime/lua

pet-prototype: pet-app-open

pet-app:
	mkdir -p build
	$(USAGI_BIN) export --target host -o $(PET_APP_ZIP) pet-runtime/lua
	rm -rf $(PET_APP_DIR)
	unzip -q -o $(PET_APP_ZIP) -d build

pet-app-open: pet-app
	open $(PET_APP_DIR)
