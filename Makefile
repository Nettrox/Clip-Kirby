APP_NAME=Clip Kirby
EXECUTABLE_NAME=MacClipboardBoard
BUNDLE_NAME=$(APP_NAME).app
BUNDLE_ID=com.clipkirby.app
BUILD_DIR=.build/release
APP_BUILD_DIR=build/$(BUNDLE_NAME)
USER_APPS_DIR=$(HOME)/Applications
INSTALLED_APP=$(USER_APPS_DIR)/$(BUNDLE_NAME)
LAUNCH_AGENTS_DIR=$(HOME)/Library/LaunchAgents
LAUNCH_AGENT_PLIST=$(LAUNCH_AGENTS_DIR)/$(BUNDLE_ID).plist

.PHONY: build app install restart enable-login disable-login clean

build:
	swift build -c release

app: build
	mkdir -p "$(APP_BUILD_DIR)/Contents/MacOS"
	mkdir -p "$(APP_BUILD_DIR)/Contents/Resources"
	cp "$(BUILD_DIR)/$(EXECUTABLE_NAME)" "$(APP_BUILD_DIR)/Contents/MacOS/ClipKirby"
	cp "Resources/Info.plist" "$(APP_BUILD_DIR)/Contents/Info.plist"
	if [ -f "Resources/AppIcon.icns" ]; then cp "Resources/AppIcon.icns" "$(APP_BUILD_DIR)/Contents/Resources/AppIcon.icns"; fi
	if [ -f "Resources/StatusIconTemplate.png" ]; then cp "Resources/StatusIconTemplate.png" "$(APP_BUILD_DIR)/Contents/Resources/StatusIconTemplate.png"; fi
	if [ -f "Resources/StatusIcon.png" ]; then cp "Resources/StatusIcon.png" "$(APP_BUILD_DIR)/Contents/Resources/StatusIcon.png"; fi
	if [ -f "Resources/MenuBarIcon.png" ]; then cp "Resources/MenuBarIcon.png" "$(APP_BUILD_DIR)/Contents/Resources/MenuBarIcon.png"; fi
	chmod +x "$(APP_BUILD_DIR)/Contents/MacOS/ClipKirby"

install: app
	mkdir -p "$(USER_APPS_DIR)"
	ditto "$(APP_BUILD_DIR)" "$(INSTALLED_APP)"
	xattr -dr com.apple.quarantine "$(INSTALLED_APP)" 2>/dev/null || true
	echo "Installed: $(INSTALLED_APP)"

restart: install
	osascript -e 'tell application "Clip Kirby" to quit' 2>/dev/null || true
	open "$(INSTALLED_APP)"

echo-login-plist:
	mkdir -p "$(LAUNCH_AGENTS_DIR)"
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' > "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '<plist version="1.0">' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '<dict>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    <key>Label</key>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    <string>$(BUNDLE_ID)</string>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    <key>ProgramArguments</key>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    <array>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '        <string>/usr/bin/open</string>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '        <string>-a</string>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '        <string>$(INSTALLED_APP)</string>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    </array>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    <key>RunAtLoad</key>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '    <true/>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '</dict>' >> "$(LAUNCH_AGENT_PLIST)"
	printf '%s\n' '</plist>' >> "$(LAUNCH_AGENT_PLIST)"

enable-login: install echo-login-plist
	launchctl unload "$(LAUNCH_AGENT_PLIST)" 2>/dev/null || true
	launchctl load "$(LAUNCH_AGENT_PLIST)"
	echo "Login startup enabled for $(APP_NAME)."

disable-login:
	launchctl unload "$(LAUNCH_AGENT_PLIST)" 2>/dev/null || true
	if [ -f "$(LAUNCH_AGENT_PLIST)" ]; then rm "$(LAUNCH_AGENT_PLIST)"; fi
	echo "Login startup disabled for $(APP_NAME)."

clean:
	swift package clean
