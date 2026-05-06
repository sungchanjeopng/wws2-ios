// Ported from app/src/main/java/com/wws2/densitymeter/ui/theme/Theme.kt
//
// Compose's `MaterialTheme(colorScheme = …)` and a fixed
// `LocalDensity(fontScale = 0.85f)` map onto SwiftUI environment values:
//
//   - Material `colorScheme.primary` etc. → AppColors.* used inline (SwiftUI
//     doesn't have a single global color scheme like MaterialTheme; we just
//     use the AppColors enum directly throughout the UI).
//   - `fontScale = 0.85f` → `.environment(\.dynamicTypeSize, .small)` to
//     suppress accessibility scaling toward the same compact size that
//     Compose was producing. Apps that need full dynamic type can drop
//     this modifier.

import SwiftUI

public struct DensityMeterTheme<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .tint(AppColors.primary)
            .background(AppColors.background.ignoresSafeArea())
            .foregroundStyle(AppColors.darkText)
            // Match Kotlin's `fontScale = 0.85f` by clamping dynamic type.
            .dynamicTypeSize(.xSmall ... .large)
    }
}
