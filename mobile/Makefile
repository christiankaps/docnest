.PHONY: help generate build test test-unit test-ui verify

DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0
CONFIGURATION ?= Debug
XCODEBUILD = xcodebuild -project DocNestMobile.xcodeproj -scheme DocNestMobile -configuration $(CONFIGURATION) -derivedDataPath .build CODE_SIGNING_ALLOWED=NO

help:
	@echo "make generate   Regenerate Xcode project (requires XcodeGen)"
	@echo "make build      Build for the iOS Simulator"
	@echo "make test-unit  Run library safety and resource tests"
	@echo "make test-ui    Run simulator UI checks"
	@echo "make verify     Build and run unit/UI tests (override DESTINATION if needed)"

generate:
	xcodegen generate --spec project.yml

build:
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' build

test:
	$(XCODEBUILD) -destination '$(DESTINATION)' -parallel-testing-enabled NO test

test-unit:
	$(XCODEBUILD) -destination '$(DESTINATION)' -parallel-testing-enabled NO -only-testing:DocNestMobileTests test

test-ui:
	$(XCODEBUILD) -destination '$(DESTINATION)' -parallel-testing-enabled NO -only-testing:DocNestMobileUITests test

verify: test
