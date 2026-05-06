// App entry point. Equivalent to `DensityMeterApp.kt` (Application class) +
// `MainActivity.kt` (Activity setContent) on Android.

import SwiftUI

@main
struct WWS2iOSApp: App {
    var body: some Scene {
        WindowGroup {
            DensityMeterTheme {
                MainShellView()
            }
        }
    }
}
