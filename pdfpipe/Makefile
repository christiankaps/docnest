.DEFAULT_GOAL := help
.PHONY: help generate build build-debug build-device build-release build-release-simulator analyze-release test test-unit test-ui test-release verify clean

DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0
CONFIGURATION ?= Debug
TEST_OPTIONS ?= -collect-test-diagnostics never -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120
PROJECT = -project PdfPipe.xcodeproj -scheme PdfPipe
SIMULATOR_SIGNING = CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
XCODEBUILD = xcodebuild $(PROJECT) -configuration $(CONFIGURATION) -derivedDataPath .build $(SIMULATOR_SIGNING)
RELEASE_DEVICE = xcodebuild $(PROJECT) -configuration Release -derivedDataPath .build-release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
RELEASE_SIMULATOR = xcodebuild $(PROJECT) -configuration Release -derivedDataPath .build-release-simulator $(SIMULATOR_SIGNING)
TEST_ARGUMENTS = -destination '$(DESTINATION)' -parallel-testing-enabled NO $(TEST_OPTIONS)

help:
	@echo "make generate                Regenerate the Xcode project from project.yml"
	@echo "make build / build-debug     Build app and share extension for Simulator"
	@echo "make build-device            Build for iOS devices without provisioning"
	@echo "make build-release           Analyze and build optimized unsigned iOS Release"
	@echo "make build-release-simulator Analyze and build optimized Simulator Release"
	@echo "make analyze-release         Run Xcode static analysis in Release configuration"
	@echo "make test                    Run all unit and UI tests"
	@echo "make test-unit               Run processing, export, persistence, cleanup tests"
	@echo "make test-ui                 Run app and share-extension UI checks"
	@echo "make test-release            Run unit tests against optimized Release code"
	@echo "make verify                  Generate, run all tests, analyze/build iOS Release"
	@echo "make clean                   Remove local build products and test results"
	@echo "Override DESTINATION for a different simulator; no target changes provisioning."

generate:
	xcodegen generate --spec project.yml

build:
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' build

build-debug:
	$(MAKE) build CONFIGURATION=Debug

build-device:
	xcodebuild $(PROJECT) -configuration $(CONFIGURATION) -derivedDataPath .build-device -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# Release build settings also enable analysis during ordinary Xcode builds/archives.
build-release:
	$(RELEASE_DEVICE) analyze build

build-release-simulator:
	$(RELEASE_SIMULATOR) -destination 'generic/platform=iOS Simulator' analyze build

analyze-release:
	$(RELEASE_DEVICE) analyze

test:
	$(XCODEBUILD) $(TEST_ARGUMENTS) test

test-unit:
	$(XCODEBUILD) $(TEST_ARGUMENTS) -only-testing:PdfPipeTests test

test-ui:
	$(XCODEBUILD) $(TEST_ARGUMENTS) -only-testing:PdfPipeUITests test

test-release:
	$(RELEASE_SIMULATOR) $(TEST_ARGUMENTS) ENABLE_TESTABILITY=YES -only-testing:PdfPipeTests test

# Keep these sequential even under make -j: Xcode shares build databases.
verify: generate
	$(MAKE) test CONFIGURATION=Debug
	$(MAKE) build-release

clean:
	rm -rf .build .build-device .build-release .build-release-simulator
