.PHONY: help generate build verify

help:
	@echo "make generate  Regenerate Xcode project (requires XcodeGen)"
	@echo "make build     Build Hello World for the iOS Simulator"
	@echo "make verify    Run the current integration gate"

generate:
	xcodegen generate --spec project.yml

build:
	xcodebuild -project DocNestMobile.xcodeproj -scheme DocNestMobile -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build

verify: build
