PROJECT := ConquerHills.xcodeproj
SCHEME := ConquerHills
PACKAGE_PATH := Packages/ConquerHillsKit
TOOL_PATH := Tools/CourseTool
SWIFT_SOURCES := App AppUITests Tools/make-app-icon.swift $(PACKAGE_PATH)/Package.swift $(PACKAGE_PATH)/Sources \
	$(PACKAGE_PATH)/Tests $(TOOL_PATH)/Package.swift $(TOOL_PATH)/Sources $(TOOL_PATH)/Tests
COURSE_TOOL := swift run --package-path $(TOOL_PATH) -c release course-tool

.PHONY: bootstrap generate open test build format lint check ui-test course-route course-elevation course-build \
	courses-check

# The main checkout, which differs from the current directory inside a git worktree.
MAIN_CHECKOUT := $(shell dirname "$$(git rev-parse --path-format=absolute --git-common-dir)")

## bootstrap: check required tools, set up Config/Local.xcconfig, generate the Xcode project
##            (in a worktree, Config/Local.xcconfig is linked to the main checkout's copy)
bootstrap:
	@command -v xcodebuild >/dev/null || { echo "Xcode is required: install it from the App Store."; exit 1; }
	@command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
	@if [ -e Config/Local.xcconfig ]; then :; \
	elif [ "$(MAIN_CHECKOUT)" != "$(CURDIR)" ] && [ -f "$(MAIN_CHECKOUT)/Config/Local.xcconfig" ]; then \
		ln -s "$(MAIN_CHECKOUT)/Config/Local.xcconfig" Config/Local.xcconfig; \
		echo "Linked Config/Local.xcconfig to the main checkout's copy."; \
	else \
		cp Config/Local.xcconfig.example Config/Local.xcconfig; \
		echo "Created Config/Local.xcconfig: set DEVELOPMENT_TEAM to run on a device."; \
	fi
	@$(MAKE) generate

## generate: regenerate the Xcode project from project.yml
generate:
	xcodegen generate --quiet

$(PROJECT)/project.pbxproj: project.yml
	xcodegen generate --quiet

## open: open the project in Xcode, generating it first if project.yml changed
open: $(PROJECT)/project.pbxproj
	open $(PROJECT)

## test: run the Swift package tests and the course tool's tests
test:
	swift test --package-path $(PACKAGE_PATH)
	swift test --package-path $(TOOL_PATH)

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

## ui-test: walk through a Test Hills run in the iOS Simulator, saving screenshots to .scratch/ui-test/ (local only)
UI_TEST_DEVICE ?= iPhone 17 Pro
ui-test: $(PROJECT)/project.pbxproj
	rm -rf .scratch/ui-test && mkdir -p .scratch/ui-test
	xcodebuild test -quiet -project $(PROJECT) -scheme $(SCHEME) -only-testing:ConquerHillsUITests \
		-destination 'platform=iOS Simulator,name=$(UI_TEST_DEVICE)' -resultBundlePath .scratch/ui-test/result.xcresult
	xcrun xcresulttool export attachments --path .scratch/ui-test/result.xcresult --output-path .scratch/ui-test

## course-route ID=<id>: route source → route.geojson, refresh osm-structures.json (network)
course-route:
	@test -n "$(ID)" || { echo "usage: make course-route ID=<course-id>"; exit 2; }
	$(COURSE_TOOL) route $(ID)

## course-elevation ID=<id>: fill or resume elevation-samples.json (network; slow, resumable)
course-elevation:
	@test -n "$(ID)" || { echo "usage: make course-elevation ID=<course-id>"; exit 2; }
	$(COURSE_TOOL) elevation $(ID)

## course-build ID=<id>: build the bundled course file and the review report (offline)
course-build:
	@test -n "$(ID)" || { echo "usage: make course-build ID=<course-id>"; exit 2; }
	$(COURSE_TOOL) build $(ID) --report "$(MAIN_CHECKOUT)/.scratch/reports"

## courses-check: rebuild every course in CourseData from committed inputs; fail if a bundled file differs
courses-check:
	@for config in CourseData/*/config.json; do \
		id=$$(basename $$(dirname $$config)); \
		swift run --package-path $(TOOL_PATH) course-tool check $$id || exit 1; \
	done

## check: lint, test, course data, and build; run before opening a PR (and in CI)
check: lint test courses-check build
