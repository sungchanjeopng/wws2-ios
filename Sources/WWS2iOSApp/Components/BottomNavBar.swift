// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/BottomNavBar.kt

import SwiftUI

private let labels = ["Main", "Echo", "Trend", "Param", "Menu"]

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
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
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
