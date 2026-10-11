.PHONY: help generate build build-device test-unit test-ui verify
DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0
CONFIGURATION ?= Debug
TEST_OPTIONS ?= -collect-test-diagnostics never -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120
XCODEBUILD = xcodebuild -project PdfPipe.xcodeproj -scheme PdfPipe -configuration $(CONFIGURATION) -derivedDataPath .build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
help:
	@echo "make generate   Regenerate the Xcode project with XcodeGen"
	@echo "make build      Build app and share extension for iOS Simulator"
	@echo "make build-device Compile app/extension for iOS devices without provisioning"
	@echo "make test-unit  Run processing, export, persistence, and cleanup tests"
	@echo "make test-ui    Run app and share-extension UI checks"
	@echo "make verify     Regenerate, build, and run all tests"
generate:
	xcodegen generate --spec project.yml
build:
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' build
build-device:
	xcodebuild -project PdfPipe.xcodeproj -scheme PdfPipe -configuration $(CONFIGURATION) -derivedDataPath .build-device -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
test-unit:
	$(XCODEBUILD) -destination '$(DESTINATION)' -parallel-testing-enabled NO $(TEST_OPTIONS) -only-testing:PdfPipeTests test
test-ui:
	$(XCODEBUILD) -destination '$(DESTINATION)' -parallel-testing-enabled NO $(TEST_OPTIONS) -only-testing:PdfPipeUITests test
verify: generate
	$(XCODEBUILD) -destination '$(DESTINATION)' -parallel-testing-enabled NO $(TEST_OPTIONS) test
