.PHONY: project test validate archive

project:
	xcodegen generate

test:
	swift test

validate:
	python3 tools/validate.py

archive:
	cd .. && zip -r TrailGuard-iOS-MVP.zip TrailGuard -x "TrailGuard/.build/*" "TrailGuard/.swiftpm/*" "TrailGuard/*.zip"
