test:
	git submodule init
	git submodule update
	which ios-sim || brew install ios-sim
	xcodebuild -project Example/CargoBay.xcodeproj -target CargoBayTests -sdk iphonesimulator -configuration Debug RUN_UNIT_TEST_WITH_IOS_SIM=YES