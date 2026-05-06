// Ported from app/src/main/java/com/wws2/densitymeter/ui/theme/AppLayout.kt
//
// Layout helpers — wide layout (landscape OR ≥ 600pt width) and tablet
// (compact size class is .regular). Use within a SwiftUI view via the
// helper struct or by reading horizontal/vertical size classes directly.

import SwiftUI

public enum AppLayout {
    /// Approximate match for the Android "screen width 600dp" breakpoint.
    /// SwiftUI gives us size classes (compact / regular) that map closely
    /// to phone vs phone-landscape / iPad respectively.
    public static let wideLayoutBreakpointPt: CGFloat = 600
}

public struct LayoutEnvironment {
    public let widthPt: CGFloat
    public let isLandscape: Bool
    public let horizontalSizeClass: UserInterfaceSizeClass?
    public let verticalSizeClass: UserInterfaceSizeClass?

    public var isWideLayout: Bool {
        isLandscape || widthPt >= AppLayout.wideLayoutBreakpointPt
    }

    /// Tablet-class device (iPad). Mirrors the Kotlin `smallestScreenWidthDp ≥ 600`
    /// heuristic — on iOS the regular horizontal size class on both axes is the
    /// closest analog.
    public var isTablet: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

extension View {
    /// Run `content` with a snapshot of the current layout environment.
    public func withLayoutEnvironment<Content: View>(
        @ViewBuilder _ content: @escaping (LayoutEnvironment) -> Content
    ) -> some View {
        GeometryReader { proxy in
            LayoutEnvironmentReader(proxy: proxy, content: content)
        }
    }
}

private struct LayoutEnvironmentReader<Content: View>: View {
    let proxy: GeometryProxy
    let content: (LayoutEnvironment) -> Content
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass

    var body: some View {
        let env = LayoutEnvironment(
            widthPt: proxy.size.width,
            isLandscape: proxy.size.width > proxy.size.height,
            horizontalSizeClass: hSizeClass,
            verticalSizeClass: vSizeClass
        )
        content(env)
    }
}
