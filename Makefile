.PHONY: build test test-syntax app dev test-app run run-test install icon grammars fmt clean

build:
	swift build

test:
	swift test

test-syntax:
	swift test --package-path Packages/QuickEditSyntax

app:
	scripts/build-app.sh release

dev:
	scripts/build-app.sh dev

test-app:
	scripts/build-app.sh test

run: dev
	open "build/QuickEdit Dev.app"

# Agents: launch the background Test build without stealing focus.
run-test: test-app
	open -g "build/QuickEdit Test.app"

install: app
	-osascript -e 'tell application id "com.itsjavi.quickedit" to quit' 2>/dev/null
	rm -rf /Applications/QuickEdit.app
	cp -R build/QuickEdit.app /Applications/QuickEdit.app

icon:
	swift scripts/make-icon.swift

grammars:
	Packages/QuickEditSyntax/scripts/vendor-grammars.sh

fmt:
	npx -y oxfmt .

clean:
	rm -rf build .build Packages/QuickEditSyntax/.build
