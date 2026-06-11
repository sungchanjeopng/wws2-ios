// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/BottomNavBar.kt

import SwiftUI

// Tab indices stay stable (Main=0, Echo=1, Param=3, Menu=4) so the
// ViewModel's tabIndex-based logic stays untouched; the Trend tab
// (index 2) is simply not offered any more.
private let tabs: [(String, Int)] = [
    ("Main", 0),
    ("Echo", 1),
    ("Param", 3),
    ("Menu", 4),
]

public struct BottomNavBar: View {
    public let currentIndex: Int
    public let onTap: (Int) -> Void

    public init(currentIndex: Int, onTap: @escaping (Int) -> Void) {
        self.currentIndex = currentIndex
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.grayLabel.opacity(0.5))
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                    let (label, i) = tab
                    let active = i == currentIndex
                    Button(action: { onTap(i) }) {
                        Text(label)
                            .font(.system(size: 15, weight: active ? .heavy : .bold))
                            .kerning(-0.3)
                            .foregroundStyle(active ? AppColors.primary : AppColors.grayLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(AppColors.white)
        }
    }
}
