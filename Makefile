.PHONY: build app dmg run run-app clean

APP_NAME := E2BBar

build:
	swift build -c release

app: build
	./Scripts/package_app.sh release

dmg: app
	./Scripts/create_dmg.sh

run:
	swift run $(APP_NAME)

run-app: app
	open "build/$(APP_NAME).app"

clean:
	rm -rf .build build
