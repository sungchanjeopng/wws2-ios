// Ported from app/src/main/java/com/wws2/densitymeter/ui/theme/AppColors.kt

import SwiftUI

public enum AppColors {
    public static let primary       = Color(hex: 0x3182F6)
    public static let darkText      = Color(hex: 0x191F28)
    public static let background    = Color(hex: 0xF2F4F6)
    public static let grayLabel     = Color(hex: 0x8B95A1)
    public static let border        = Color(hex: 0xD1D6DB)
    public static let error         = Color(hex: 0xEB5757)
    public static let success       = Color(hex: 0x34C759)
    public static let temperature   = Color(hex: 0xE03131)
    public static let white         = Color(hex: 0xFFFFFF)
    public static let lightGray     = Color(hex: 0xF8F9FA)
    public static let subText       = Color(hex: 0x4E5968)
    public static let weakText      = Color(hex: 0xB0B8C1)
    public static let pillDisconnected = Color(hex: 0xE8EBED)
    public static let cardShadow    = Color.black.opacity(0x0F / 255.0)
}

extension Color {
    /// Initialize a `Color` from a 24-bit RGB value (0xRRGGBB) with optional alpha.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
