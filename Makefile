SHELL := /bin/bash

PROJECT ?= DocNest.xcodeproj
SCHEME ?= DocNest
CONFIGURATION ?= Debug
DERIVED_DATA_DIR ?= /tmp/docnest-derived
RELEASE_DERIVED_DATA_DIR ?= /tmp/docnest-release-derived
ARCHIVE_PATH ?= /tmp/docnest-release/DocNest.xcarchive
DESTINATION ?= platform=macOS

XCODEBUILD := xcodebuild
XCODE_FLAGS := -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA_DIR)
TEST_DESTINATION_FLAGS := -destination "$(DESTINATION)"
WARNING_POLICY_FLAGS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES CLANG_TREAT_WARNINGS_AS_ERRORS=YES
RELEASE_OPTIMIZATION_FLAGS := SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s DEAD_CODE_STRIPPING=YES LLVM_LTO=YES COPY_PHASE_STRIP=YES STRIP_INSTALLED_PRODUCT=YES

.DEFAULT_GOAL := help

.PHONY: help build run test test-unit test-ui build-for-testing analyze release-build archive dmg clean

help:
	@printf "DocNest build targets:\n"
	@printf "  make build             Build the app (Debug by default)\n"
	@printf "  make run               Build and open the app (Debug by default)\n"
	@printf "  make test              Run the full test suite\n"
	@printf "  make test-unit         Run DocNestTests only\n"
	@printf "  make test-ui           Run DocNestUITests only\n"
	@printf "  make build-for-testing Build test bundles without running tests\n"
	@printf "  make analyze           Run Xcode static analysis\n"
	@printf "  make release-build     Build a highly optimized Release app\n"
	@printf "  make archive           Create a Release xcarchive\n"
	@printf "  make dmg               Build a local DMG via scripts/build-dmg.sh\n"
	@printf "  make clean             Clean build products\n"

build:
	$(XCODEBUILD) $(XCODE_FLAGS) -configuration $(CONFIGURATION) build $(WARNING_POLICY_FLAGS)

run: build
	open "$(DERIVED_DATA_DIR)/Build/Products/$(CONFIGURATION)/DocNest.app"

test:
	$(XCODEBUILD) $(XCODE_FLAGS) $(TEST_DESTINATION_FLAGS) test $(WARNING_POLICY_FLAGS)

test-unit:
	$(XCODEBUILD) $(XCODE_FLAGS) $(TEST_DESTINATION_FLAGS) test -only-testing:DocNestTests $(WARNING_POLICY_FLAGS)

test-ui:
	$(XCODEBUILD) $(XCODE_FLAGS) $(TEST_DESTINATION_FLAGS) test -only-testing:DocNestUITests $(WARNING_POLICY_FLAGS)

build-for-testing:
	$(XCODEBUILD) $(XCODE_FLAGS) $(TEST_DESTINATION_FLAGS) build-for-testing $(WARNING_POLICY_FLAGS)

analyze:
	$(XCODEBUILD) $(XCODE_FLAGS) -configuration $(CONFIGURATION) analyze $(WARNING_POLICY_FLAGS)

release-build:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(RELEASE_DERIVED_DATA_DIR) build $(WARNING_POLICY_FLAGS) $(RELEASE_OPTIMIZATION_FLAGS)

archive:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release -archivePath $(ARCHIVE_PATH) archive SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=NO $(WARNING_POLICY_FLAGS) $(RELEASE_OPTIMIZATION_FLAGS)

dmg:
	$(WARNING_POLICY_FLAGS) scripts/build-dmg.sh

clean:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA_DIR) clean
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(RELEASE_DERIVED_DATA_DIR) clean
