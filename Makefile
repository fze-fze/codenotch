# Xcode's location, asked for rather than assumed. Hardcoding
# /Applications/Xcode.app fails outright on a machine running an Xcode beta,
# where the directory simply does not exist — and `xcode-select -p` is the
# same answer every other tool in the toolchain already uses.
export DEVELOPER_DIR := $(shell xcode-select -p)

PROJECT := Codenotch.xcodeproj
SCHEME  := Codenotch
DEST    := platform=macOS,arch=arm64

.PHONY: gen build test run install clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug test

run: build
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $$2; exit}')/Codenotch.app; \
	pkill -x Codenotch || true; \
	open "$$APP"

# Put the built app in /Applications, where it can be opened from Spotlight,
# the Dock and Login Items like any other app.
#
# `make run` launches out of DerivedData, which is the right place for a build
# you are about to change again — but it is scratch space. Xcode empties it,
# `make clean` empties it, and an app you actually use every day should not
# live somewhere that gets deleted as housekeeping.
#
# Debug and not Release, on purpose: Release signs with the Developer ID this
# fork does not have. The Debug build carries the local certificate, and that
# certificate is what the keychain's "Always Allow" is remembered against —
# installing a differently signed copy would ask for the grant all over again.
#
# Replaces whatever is already at that path, which is the point: it is how a
# copy installed from the dmg gets superseded by this one. Nothing else under
# /Applications is touched.
install: build
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $$2; exit}')/Codenotch.app; \
	test -d "$$APP" || { echo "no built app at $$APP"; exit 1; }; \
	pkill -x Codenotch || true; \
	rm -rf /Applications/Codenotch.app; \
	cp -R "$$APP" /Applications/Codenotch.app; \
	open /Applications/Codenotch.app; \
	echo "installed /Applications/Codenotch.app"

clean:
	rm -rf build DerivedData $(PROJECT)

