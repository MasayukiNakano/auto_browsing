.PHONY: all build wrap clean java

BUILD_DIR = .build
CONFIG = release
APP_NAME = AutoBrowsingApp
APP_PATH = dist/$(APP_NAME).app
RESOURCE_BUNDLE = $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)_$(APP_NAME).bundle
JAVA_STRATEGY_SRC = ../java-strategy
JAVA_STRATEGY_INSTALL = $(JAVA_STRATEGY_SRC)/build/install/load-more-strategy
PYTHON3 = python3

all: wrap

build:
	swift build --configuration $(CONFIG)

java:
	cd $(JAVA_STRATEGY_SRC) && ./gradlew installDist

wrap: java build
	@mkdir -p $(APP_PATH)/Contents/MacOS
	@mkdir -p $(APP_PATH)/Contents/Resources
	@cp $(BUILD_DIR)/$(CONFIG)/$(APP_NAME) $(APP_PATH)/Contents/MacOS/$(APP_NAME)
	@chmod +x $(APP_PATH)/Contents/MacOS/$(APP_NAME)
	@cp Info.plist.template $(APP_PATH)/Contents/Info.plist
	@cp ../scripts/aggregate_links.py $(APP_PATH)/Contents/Resources/aggregate_links.py
	@if [ -d $(RESOURCE_BUNDLE) ]; then \
		rm -rf $(APP_PATH)/Contents/Resources/$(APP_NAME)_$(APP_NAME).bundle; \
		cp -R $(RESOURCE_BUNDLE) $(APP_PATH)/Contents/Resources/; \
	fi
	@if [ -d $(JAVA_STRATEGY_INSTALL) ]; then \
		rm -rf $(APP_PATH)/Contents/Resources/load-more-strategy; \
		cp -R $(JAVA_STRATEGY_INSTALL) $(APP_PATH)/Contents/Resources/; \
	fi

clean:
	rm -rf $(BUILD_DIR) dist
	swift package clean
