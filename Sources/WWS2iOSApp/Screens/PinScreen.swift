// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/PinScreen.kt
//
// Custom 4-digit PIN keypad — does not use the system numeric keyboard.
// Displays four dot indicators that fill as digits are entered, and a
// 12-key (1-9, blank, 0, delete) layout. Auto-submits when the 4th digit
// is entered. Honors landscape vs portrait via GeometryReader.

import SwiftUI

public struct PinScreen: View {
    public let showBack: Bool
    public let onPinEntered: (Int) -> Void
    public let onBack: () -> Void

    @State private var input: String = ""

    public init(showBack: Bool = false,
                onPinEntered: @escaping (Int) -> Void = { _ in },
                onBack: @escaping () -> Void = {}) {
        self.showBack = showBack
        self.onPinEntered = onPinEntered
        self.onBack = onBack
    }

    private func onKey(_ key: String) {
        if input.count >= 4 { return }
        input += key
        if input.count == 4 {
            let pin = Int(input) ?? 0
            onPinEntered(pin)
        }
    }

    private func onDelete() {
        if input.isEmpty { return }
        input.removeLast()
    }

    public var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            ZStack(alignment: .topLeading) {
                AppColors.white.ignoresSafeArea()
                VStack(spacing: 0) {
                    if showBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.darkText)
                                .padding(16)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(height: 16)
                    }

                    if wide {
                        HStack(spacing: 0) {
                            VStack {
                                Spacer()
                                pinHeader
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            PinKeypad(onKey: onKey, onDelete: onDelete)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 24)
                            pinHeader
                            Spacer().frame(height: 24)
                            PinKeypad(onKey: onKey, onDelete: onDelete)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var pinHeader: some View {
        VStack(spacing: 32) {
            Text("Enter Password")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.8)
                .foregroundStyle(AppColors.darkText)
            HStack(spacing: 24) {
                ForEach(0..<4, id: \.self) { i in
                    let filled = i < input.count
                    Circle()
                        .fill(filled ? AppColors.darkText : Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(filled ? AppColors.darkText : AppColors.border, lineWidth: 2)
                        )
                }
            }
        }
    }
}

private struct PinKeypad: View {
    let onKey: (String) -> Void
    let onDelete: () -> Void
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "del"]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColors.background).frame(height: 1)
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { col in
                        let key = keys[row * 3 + col]
                        Button(action: {
                            if key == "del" { onDelete() }
                            else if !key.isEmpty { onKey(key) }
                        }) {
                            ZStack {
                                Color.clear
                                if key == "del" {
                                    Image(systemName: "delete.left")
                                        .font(.system(size: 24))
                                        .foregroundStyle(AppColors.darkText)
                                } else if !key.isEmpty {
                                    Text(key)
                                        .font(.system(size: 34, weight: .light))
                                        .foregroundStyle(AppColors.darkText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1.5, contentMode: .fit)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(key.isEmpty)
                    }
                }
            }
        }
    }
}
