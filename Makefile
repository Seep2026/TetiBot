USAGI_BIN ?= ./engine/usagi/target/release/usagi

.PHONY: assets-master-128 check-aseprite-env pet-prototype

assets-master-128:
	./tools/asset-build/build_master_128.sh

check-aseprite-env:
	./tools/asset-build/check_aseprite_env.sh

pet-prototype:
	$(USAGI_BIN) run pet-runtime/lua
