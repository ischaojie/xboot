APP        := xboot
BUILD      := build
BUNDLE     := $(BUILD)/$(APP).app

SDK        := $(shell xcrun --show-sdk-path)
CC         := clang
CFLAGS     := -fobjc-arc -fmodules -isysroot $(SDK) -mmacosx-version-min=14.0 \
              -Wall -Wextra -Wno-unused-parameter -O2 -I Sources
LDFLAGS    := -framework Cocoa
SOURCES    := $(wildcard Sources/*.m)
ICON       := Resources/xboot.icns

.PHONY: all run test icon clean

all: $(BUNDLE)/Contents/MacOS/$(APP)

icon: $(ICON)
	@echo "built $(ICON)"

$(ICON): tools/IconGen.m
	@rm -rf $(BUILD)/xboot.iconset
	@mkdir -p $(BUILD)/xboot.iconset
	@$(CC) $(CFLAGS) -framework ImageIO tools/IconGen.m -o $(BUILD)/icongen
	@$(BUILD)/icongen $(BUILD)/xboot.iconset
	@iconutil -c icns $(BUILD)/xboot.iconset -o $(ICON)

$(BUNDLE)/Contents/MacOS/$(APP): $(SOURCES) Resources/Info.plist $(ICON)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o $@
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp $(ICON) $(BUNDLE)/Contents/Resources/xboot.icns
	@codesign --force --sign - $(BUNDLE) 2>/dev/null
	@echo "built $(BUNDLE)"

run: all
	@pkill -x $(APP) 2>/dev/null || true
	@open $(BUNDLE)

test: $(BUILD)/tests
	@$(BUILD)/tests

$(BUILD)/tests: $(wildcard Sources/*.m Tests/*.m) Sources/*.h
	@mkdir -p $(BUILD)
	@$(CC) $(CFLAGS) -Itests $(filter-out Sources/main.m,$(SOURCES)) Tests/*.m $(LDFLAGS) -o $@

clean:
	rm -rf $(BUILD)
