USAGI_MANIFEST ?= engine/usagi/Cargo.toml
USAGI_BIN ?= $(abspath engine/usagi/target/release/usagi)
TETI_PET_PROJECT ?= $(abspath pet-runtime/lua)
DELTA_CORE_DIR ?= ../core
DELTA_CORE_RECOMMENDED_REV := 24848c0265485d9254b77010e54ba756428321da
DELTA_CHAT_RPC_SERVER ?= $(abspath $(DELTA_CORE_DIR))/target/release/deltachat-rpc-server
PET_APP_ZIP := build/Teti-macos.zip
PET_APP_DIR := build/Teti.app

.PHONY: assets-master-128 check-aseprite-env hat-runtime-check usagi-build pet-run pet-dev pet-prototype pet-app pet-app-open chatmail-core-source-check chatmail-core-revision chatmail-core chatmail-check chatmail-build chatmail-run

assets-master-128:
	./tools/asset-build/build_master_128.sh
	$(MAKE) hat-runtime-check

check-aseprite-env:
	./tools/asset-build/check_aseprite_env.sh

hat-runtime-check:
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_hat_assets.py

usagi-build:
	cargo build --release --manifest-path "$(USAGI_MANIFEST)"

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

chatmail-core-source-check:
	test -f "$(DELTA_CORE_DIR)/deltachat-rpc-server/Cargo.toml"

chatmail-core-revision: chatmail-core-source-check
	@echo "Core source: $$(cd "$(DELTA_CORE_DIR)" && pwd)"
	@echo "Core revision: $$(git -C "$(DELTA_CORE_DIR)" rev-parse HEAD)"
	@echo "Recommended:  $(DELTA_CORE_RECOMMENDED_REV)"

chatmail-core: chatmail-core-source-check
	cargo build --release -p deltachat-rpc-server --manifest-path "$(DELTA_CORE_DIR)/Cargo.toml"

chatmail-check:
	cargo test --manifest-path src-tauri/Cargo.toml

chatmail-build: usagi-build chatmail-core
	DELTA_CORE_DIR="$(abspath $(DELTA_CORE_DIR))" DELTA_CHAT_RPC_SERVER="$(DELTA_CHAT_RPC_SERVER)" USAGI_BIN="$(USAGI_BIN)" TETI_PET_PROJECT="$(TETI_PET_PROJECT)" cargo build --release --manifest-path src-tauri/Cargo.toml

chatmail-run: usagi-build chatmail-core
	DELTA_CORE_DIR="$(abspath $(DELTA_CORE_DIR))" DELTA_CHAT_RPC_SERVER="$(DELTA_CHAT_RPC_SERVER)" USAGI_BIN="$(USAGI_BIN)" TETI_PET_PROJECT="$(TETI_PET_PROJECT)" cargo run --manifest-path src-tauri/Cargo.toml
