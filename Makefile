USAGI_BIN ?= ./engine/usagi/target/release/usagi
PET_APP_ZIP := build/Teti-macos.zip
PET_APP_DIR := build/Teti.app

.PHONY: assets-master-128 check-aseprite-env hat-runtime-check pet-run pet-dev pet-prototype pet-app pet-app-open

assets-master-128:
	./tools/asset-build/build_master_128.sh
	$(MAKE) hat-runtime-check

check-aseprite-env:
	./tools/asset-build/check_aseprite_env.sh

hat-runtime-check:
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_hat_assets.py

pet-run: hat-runtime-check
	$(USAGI_BIN) run pet-runtime/lua

pet-dev: hat-runtime-check
	$(USAGI_BIN) dev pet-runtime/lua

pet-prototype: pet-app-open

pet-app: hat-runtime-check
	mkdir -p build
	$(USAGI_BIN) export --target host -o $(PET_APP_ZIP) pet-runtime/lua
	rm -rf $(PET_APP_DIR)
	unzip -q -o $(PET_APP_ZIP) -d build

pet-app-open: pet-app
	open $(PET_APP_DIR)
