PROJECT := ConquerHills.xcodeproj
SCHEME := ConquerHills
PACKAGE_PATH := Packages/ConquerHillsKit
SWIFT_SOURCES := App $(PACKAGE_PATH)/Package.swift $(PACKAGE_PATH)/Sources $(PACKAGE_PATH)/Tests

.PHONY: bootstrap generate open test build format lint check

## bootstrap: check required tools, create Config/Local.xcconfig, generate the Xcode project
bootstrap:
	@command -v xcodebuild >/dev/null || { echo "Xcode is required: install it from the App Store."; exit 1; }
	@command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
	@test -f Config/Local.xcconfig || { cp Config/Local.xcconfig.example Config/Local.xcconfig; \
		echo "Created Config/Local.xcconfig: set DEVELOPMENT_TEAM to run on a device."; }
	@$(MAKE) generate

## generate: regenerate the Xcode project from project.yml
generate:
	xcodegen generate --quiet

$(PROJECT)/project.pbxproj: project.yml
	xcodegen generate --quiet

## open: open the project in Xcode, generating it first if project.yml changed
open: $(PROJECT)/project.pbxproj
	open $(PROJECT)

## test: run the Swift package tests
test:
	swift test --package-path $(PACKAGE_PATH)

## build: build the app for the iOS Simulator without code signing
build: $(PROJECT)/project.pbxproj
	xcodebuild build -quiet \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		CODE_SIGNING_ALLOWED=NO

## format: format all Swift sources in place
format:
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

## lint: check formatting; fails on any violation
lint:
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

## check: lint, test, and build; run before opening a PR (and in CI)
check: lint test build
