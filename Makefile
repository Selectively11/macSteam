CC       := clang
CXX      := clang++
ARCH     := arm64
MIN_VER  := 15.0

CFLAGS   := -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) \
            -std=c17 -O2 -Wall -Wextra -Wno-unused-parameter \
            -fPIC -MMD -MP \
            -Isrc -Ivendor -Ivendor/dobby/include
LDFLAGS  := -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) \
            -dynamiclib -install_name @rpath/macsteam.dylib

FRAMEWORKS := -framework CoreFoundation -framework CFNetwork

DOBBY_REV := 5dfc8546954ce3b3198132ab13fddb89ee92cdd7
DOBBY_DIR := build
DOBBY_LIBS := $(DOBBY_DIR)/libdobby.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libdobby_symbol_resolver.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libmacho_ctx_kit.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libshared_cache_ctx_kit.a \
              $(DOBBY_DIR)/external/osbase/libosbase.a \
              $(DOBBY_DIR)/external/logging/liblogging.a

SRCS := src/core/loader.c \
        src/core/ctx.c \
        src/core/macho.c \
        src/core/reconcile.c \
        src/core/session.c \
        src/core/stats_cache.c \
        src/feats/apps.c \
        src/feats/dlc.c \
        src/feats/package.c \
        src/feats/license.c \
        src/feats/schema_owners.c \
        src/feats/depot.c \
        src/feats/ticket.c \
        src/util/log.c \
        src/util/file.c \
        src/util/hex.c \
        src/config/config.c \
        src/resolver/aob.c \
        src/resolver/anchor.c \
        src/resolver/sigdb.c \
        src/resolver/resolver.c \
        src/hooks/hooks.c \
        src/hooks/hook_apps.c \
        src/hooks/hook_depot.c \
        src/hooks/hook_dlc.c \
        src/hooks/hook_package.c \
        src/hooks/hook_license.c \
        src/hooks/hook_manifest.c \
        src/hooks/hook_relaunch.c \
        src/hooks/hook_stats.c \
        src/hooks/hook_ticket.c \
        src/hooks/hook_whatsnew.c \
        vendor/cJSON.c

OUT_DIR  := out
ARM64_DYLIB := $(OUT_DIR)/macsteam.arm64.dylib
X86_STUB    := $(OUT_DIR)/macsteam.x86_64.dylib
TARGET      := $(OUT_DIR)/macsteam.dylib
OBJS     := $(patsubst %.c,$(OUT_DIR)/%.o,$(SRCS))
DEPS     := $(OBJS:.o=.d)

.PHONY: all clean rebuild test probe

all: $(TARGET)

$(ARM64_DYLIB): $(OBJS) | dobby
	@mkdir -p $(dir $@)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(DOBBY_LIBS) $(FRAMEWORKS) -lc++

$(X86_STUB): src/stub_x86_64.c
	@mkdir -p $(dir $@)
	$(CC) -arch x86_64 -mmacosx-version-min=$(MIN_VER) \
		-dynamiclib -install_name @rpath/macsteam.dylib \
		-o $@ $<

$(TARGET): $(ARM64_DYLIB) $(X86_STUB)
	lipo -create $^ -output $@
	codesign -fs - $@
	@echo "==> Built: $@"

$(OUT_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(OUT_DIR)

rebuild: clean all

PROBE_SRC := tests/config_probe.c
PROBE_BIN := $(OUT_DIR)/tests/config_probe

STATS_PROBE_SRC := tests/stats_resolve_probe.c
STATS_PROBE_BIN := $(OUT_DIR)/tests/stats_resolve_probe

AOB_PROBE_SRC := tests/aob_probe.c
AOB_PROBE_BIN := $(OUT_DIR)/tests/aob_probe

ANCHOR_PROBE_SRC := tests/anchor_probe.c
ANCHOR_PROBE_BIN := $(OUT_DIR)/tests/anchor_probe

probe:
	@if [ -f "$(PROBE_SRC)" ]; then $(MAKE) $(PROBE_BIN); \
	 else echo "==> No local tests, skipping probe."; fi

$(PROBE_BIN): $(PROBE_SRC) src/config/config.c src/util/log.c src/util/file.c src/config/config.h
	@mkdir -p $(dir $@)
	$(CC) -std=c17 -Wall -Wextra -Isrc -o $@ $(PROBE_SRC) src/config/config.c src/util/log.c src/util/file.c
	@echo "==> Built probe: $@"

$(STATS_PROBE_BIN): $(STATS_PROBE_SRC) src/core/stats_cache.c src/util/log.c src/util/file.c
	@mkdir -p $(dir $@)
	$(CC) -std=c17 -Wall -Wextra -Isrc -o $@ $(STATS_PROBE_SRC) src/util/log.c src/util/file.c
	@echo "==> Built probe: $@"

$(AOB_PROBE_BIN): $(AOB_PROBE_SRC) src/resolver/aob.c src/util/log.c src/util/hex.c src/util/file.c src/resolver/aob.h
	@mkdir -p $(dir $@)
	$(CC) -std=c17 -Wall -Wextra -Isrc -o $@ $(AOB_PROBE_SRC) src/util/log.c src/util/hex.c src/util/file.c
	@echo "==> Built probe: $@"

$(ANCHOR_PROBE_BIN): $(ANCHOR_PROBE_SRC) src/resolver/anchor.c src/core/macho.c src/util/log.c src/util/file.c src/resolver/anchor.h
	@mkdir -p $(dir $@)
	$(CC) -std=c17 -Wall -Wextra -Isrc -o $@ $(ANCHOR_PROBE_SRC) src/util/log.c src/util/file.c
	@echo "==> Built probe: $@"

test:
	@if [ ! -d macsteam-app/Tests ]; then echo "==> No local tests, skipping."; exit 0; fi; \
	 $(MAKE) $(PROBE_BIN) $(STATS_PROBE_BIN) $(AOB_PROBE_BIN) $(ANCHOR_PROBE_BIN); \
	 echo "==> Running C stats-resolver probe..."; \
	 $(STATS_PROBE_BIN); \
	 echo "==> Running C aob-scanner probe..."; \
	 $(AOB_PROBE_BIN); \
	 echo "==> Running C anchor-resolver probe..."; \
	 MACSTEAM_SCRATCH="$(OUT_DIR)/tests" $(ANCHOR_PROBE_BIN); \
	 echo "==> Running macsteam-app tests..."; \
	 cd macsteam-app && \
	   MACSTEAM_PROBE="$(CURDIR)/$(PROBE_BIN)" \
	   MACSTEAM_CFG="$(HOME)/Library/Application Support/macsteam/config.yaml" \
	   swift test

-include $(DEPS)

.PHONY: dobby
dobby:
	@if [ ! -d vendor/dobby/.git ]; then \
		echo "==> Cloning Dobby..."; \
		git clone https://github.com/jmpews/Dobby.git vendor/dobby; \
	fi
	@if [ "$$(git -C vendor/dobby rev-parse HEAD)" != "$(DOBBY_REV)" ]; then \
		echo "==> Checking out pinned Dobby revision $(DOBBY_REV)..."; \
		git -C vendor/dobby fetch --depth=1 origin $(DOBBY_REV); \
		git -C vendor/dobby checkout --detach $(DOBBY_REV); \
	fi
	@if [ ! -f "$(DOBBY_DIR)/libdobby.a" ]; then \
		echo "==> Building Dobby from source..."; \
		cmake -S vendor/dobby -B "$(DOBBY_DIR)" \
			-DCMAKE_OSX_ARCHITECTURES=arm64 \
			-DCMAKE_OSX_DEPLOYMENT_TARGET=$(MIN_VER) \
			-DDOBBY_DEBUG=OFF \
			-G "Unix Makefiles"; \
		$(MAKE) -C "$(DOBBY_DIR)" -j$$(sysctl -n hw.ncpu); \
	fi
