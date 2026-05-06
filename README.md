# WWS2 iOS

WESSWARE iOS app — port of the Android `wws2_android` Kotlin project to native Swift / SwiftUI.

## Layout

```
Sources/
  WWS2Core/      # data models, parsers, domain logic (pure Swift)
  WWS2BLE/       # CoreBluetooth-based BLE communication
  WWS2iOSApp/    # SwiftUI app target sources
Tests/
  WWS2CoreTests/
  WWS2BLETests/
iOSApp/
  Info.plist     # iOS app target Info.plist
project.yml      # XcodeGen config (regenerates WESSWARE.xcodeproj)
Package.swift    # Swift Package (WWS2Core + WWS2BLE)
```

## Building

### Library + tests (any platform with Swift toolchain)

```bash
swift build
swift test
```

### Full iOS app (macOS + Xcode 16+ required)

```bash
brew install xcodegen
xcodegen generate
open WESSWARE.xcodeproj
```

CI builds the iOS app for the Simulator on every push (see `.github/workflows/build.yml`).

## Status

Porting from `D:/tom/ble/ble/ble0413/wws2_android` (Kotlin/Jetpack Compose) in phases:

- [ ] Phase 1: data models (`model/*.kt`)
- [ ] Phase 2: BLE protocol primitives (CRC, framing, commands)
- [ ] Phase 3: parsers (frame, echo, trend stream)
- [ ] Phase 4: BLE communication (CoreBluetooth)
- [ ] Phase 5: repository / use cases
- [ ] Phase 6: SwiftUI screens (port from Compose)
- [ ] Phase 7: integration test on iOS Simulator
