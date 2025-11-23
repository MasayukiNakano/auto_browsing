.PHONY: all build wrap clean java

BUILD_DIR = .build
CONFIG = release
APP_NAME = AutoBrowsingApp
DIST_DIR = dist
DIST_APP_PATH = $(DIST_DIR)/$(APP_NAME).app
TMPDIR ?= /tmp
STAGING_ROOT = $(TMPDIR)/$(APP_NAME)-stage
APP_PATH = $(STAGING_ROOT)/$(APP_NAME).app
RESOURCE_BUNDLE = $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)_$(APP_NAME).bundle
JAVA_STRATEGY_SRC = ../java-strategy
JAVA_STRATEGY_INSTALL = $(JAVA_STRATEGY_SRC)/build/install/load-more-strategy
SWIFT_STDLIB_TOOL = xcrun swift-stdlib-tool
INSTALL_NAME_TOOL = install_name_tool
CODESIGN = codesign
CODESIGN_IDENTITY ?= -
REMOVE_XATTRS = com.apple.FinderInfo com.apple.ResourceFork com.apple.fileprovider.fpfs\#P com.apple.macl
PYTHON3 = python3

all: wrap

build:
	swift build --configuration $(CONFIG)

java:
	cd $(JAVA_STRATEGY_SRC) && ./gradlew installDist

wrap: java build
	@rm -rf $(STAGING_ROOT)
	@rm -rf $(APP_PATH)
	@mkdir -p $(APP_PATH)/Contents/MacOS
	@mkdir -p $(APP_PATH)/Contents/Resources
	@cp -X $(BUILD_DIR)/$(CONFIG)/$(APP_NAME) $(APP_PATH)/Contents/MacOS/$(APP_NAME)
	@chmod +x $(APP_PATH)/Contents/MacOS/$(APP_NAME)
	@cp -X Info.plist.template $(APP_PATH)/Contents/Info.plist
	@cp -X ../scripts/aggregate_links.py $(APP_PATH)/Contents/Resources/aggregate_links.py
	@cp -X Sources/Resources/AppIcon.icns $(APP_PATH)/Contents/Resources/AppIcon.icns
	@if [ -d $(RESOURCE_BUNDLE) ]; then \
		rm -rf $(APP_PATH)/Contents/Resources/$(APP_NAME)_$(APP_NAME).bundle; \
		cp -R -X $(RESOURCE_BUNDLE) $(APP_PATH)/Contents/Resources/; \
	fi
	@if [ -d $(JAVA_STRATEGY_INSTALL) ]; then \
		rm -rf $(APP_PATH)/Contents/Resources/load-more-strategy; \
		cp -R -X $(JAVA_STRATEGY_INSTALL) $(APP_PATH)/Contents/Resources/; \
	fi
	@mkdir -p $(APP_PATH)/Contents/Frameworks
	@$(SWIFT_STDLIB_TOOL) --copy --scan-executable $(APP_PATH)/Contents/MacOS/$(APP_NAME) --destination $(APP_PATH)/Contents/Frameworks --platform macosx --strip-bitcode
	@$(INSTALL_NAME_TOOL) -add_rpath "@executable_path/../Frameworks" $(APP_PATH)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@for attr in $(REMOVE_XATTRS); do \
		xattr -d -r $$attr $(APP_PATH) >/dev/null 2>&1 || true; \
	done
	@xattr -cr $(APP_PATH) >/dev/null 2>&1 || true
	@$(CODESIGN) --force --deep --options runtime --sign "$(CODESIGN_IDENTITY)" $(APP_PATH)
	@rm -rf $(DIST_APP_PATH)
	@mkdir -p $(DIST_DIR)
	@cp -R $(APP_PATH) $(DIST_APP_PATH)
	@rm -rf $(STAGING_ROOT)

clean:
	rm -rf $(BUILD_DIR) dist
	swift package clean
