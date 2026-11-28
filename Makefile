.PHONY: bump project build test lint format check dmg run clean install

XCB = xcodebuild -project Friday.xcodeproj -scheme Friday -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData

project:            ## Regenerate Friday.xcodeproj from project.yml
	xcodegen generate

build:              ## Debug build
	$(XCB) build -quiet

test:               ## Run unit tests
	$(XCB) test -quiet

lint:               ## Check formatting
	xcrun swift-format lint --strict --recursive Friday FridayTests

format:             ## Apply formatting
	xcrun swift-format format --in-place --recursive Friday FridayTests

check: lint test    ## Everything CI runs
	Scripts/check-no-network.sh

dmg:                ## Release build packaged as build/Friday.dmg
	Scripts/build-dmg.sh

install:            ## Build Release, sign with the local identity, install to /Applications
	Scripts/install-local.sh

run: build          ## Build and launch the debug app
	open build/DerivedData/Build/Products/Debug/Friday.app

bump:               ## Bump version: make bump VERSION=x.y.z [DRY=--dry-run]
	Scripts/bump-version.sh $(DRY) $(VERSION)

clean:
	rm -rf build
