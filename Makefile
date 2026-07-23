.PHONY: project test validate archive

project:
	xcodegen generate

test:
	swift test

validate:
	python3 tools/validate.py

archive:
	cd .. && zip -r Aurora-iOS-MVP.zip Aurora -x "Aurora/.build/*" "Aurora/.swiftpm/*" "Aurora/*.zip"
