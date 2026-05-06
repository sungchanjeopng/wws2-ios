// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/TopBar.kt

import SwiftUI

public struct TopBar: View {
    public let isConnected: Bool
    public let statusLabel: String
    public let title: String
    public var showBack: Bool = false
    public var rxBlink: Bool = false
    public var aiActive: Bool = false
    public var onBackTap: () -> Void = {}
    public var onBleTap: () -> Void = {}
    public var onChatTap: () -> Void = {}

    public init(
        isConnected: Bool,
        statusLabel: String,
        title: String,
        showBack: Bool = false,
        rxBlink: Bool = false,
        aiActive: Bool = false,
        onBackTap: @escaping () -> Void = {},
        onBleTap: @escaping () -> Void = {},
        onChatTap: @escaping () -> Void = {}
    ) {
        self.isConnected = isConnected
        self.statusLabel = statusLabel
        self.title = title
        self.showBack = showBack
        self.rxBlink = rxBlink
        self.aiActive = aiActive
        self.onBackTap = onBackTap
        self.onBleTap = onBleTap
        self.onChatTap = onChatTap
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                if showBack {
                    Button(action: onBackTap) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.darkText)
                    }
                    .buttonStyle(.plain)
                }
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .kerning(-0.8)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
            }
            AiSparkleButton(active: aiActive, onTap: onChatTap)
            BlePillButton(
                isConnected: isConnected,
                label: statusLabel,
                rxBlink: rxBlink,
                onTap: onBleTap
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.white)
    }
}

public struct AiSparkleButton: View {
    public var active: Bool = false
    public var onTap: () -> Void = {}

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Text("✨").font(.system(size: 12))
                Text("AI")
                    .font(.system(size: 16, weight: .bold))
                    .kerning(-0.2)
            }
            .foregroundStyle(active ? Color.white : AppColors.grayLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if active {
                        LinearGradient(
                            colors: [Color(hex: 0x7C3AED), Color(hex: 0x3B82F6)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    } else {
                        AppColors.pillDisconnected
                    }
                }
            )
            .clipShape(Capsule())
            .shadow(color: active ? Color(hex: 0x7C3AED).opacity(0.3) : .clear,
                    radius: active ? 6 : 0)
        }
        .buttonStyle(.plain)
    }
}

public struct BlePillButton: View {
    public let isConnected: Bool
    public let label: String
    public var rxBlink: Bool = false
    public var onTap: () -> Void = {}

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.white : AppColors.grayLabel)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(isConnected ? Color.white : AppColors.grayLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isConnected
                    ? AppColors.success.opacity(rxBlink ? 0.7 : 1.0)
                    : AppColors.pillDisconnected
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
