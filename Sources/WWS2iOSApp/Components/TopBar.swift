// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/TopBar.kt
//
// Optional assistant entrypoints are intentionally omitted in the iOS port.
// The product scope for this build is BLE/device operation only.

import SwiftUI

public struct TopBar: View {
    public let isConnected: Bool
    public let statusLabel: String
    public let title: String
    public var showBack: Bool = false
    public var rxBlink: Bool = false
    public var isReconnecting: Bool = false
    public var onBackTap: () -> Void = {}
    public var onBleTap: () -> Void = {}

    public init(
        isConnected: Bool,
        statusLabel: String,
        title: String,
        showBack: Bool = false,
        rxBlink: Bool = false,
        isReconnecting: Bool = false,
        onBackTap: @escaping () -> Void = {},
        onBleTap: @escaping () -> Void = {}
    ) {
        self.isConnected = isConnected
        self.statusLabel = statusLabel
        self.title = title
        self.showBack = showBack
        self.rxBlink = rxBlink
        self.isReconnecting = isReconnecting
        self.onBackTap = onBackTap
        self.onBleTap = onBleTap
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }

            BlePillButton(
                isConnected: isConnected,
                label: statusLabel,
                rxBlink: rxBlink,
                isReconnecting: isReconnecting,
                onTap: onBleTap
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.white)
    }
}

public struct BlePillButton: View {
    public let isConnected: Bool
    public let label: String
    public var rxBlink: Bool = false
    public var isReconnecting: Bool = false
    public var onTap: () -> Void = {}

    // 재연결 중일 때 점 깜빡임용 불투명도
    @State private var dotOpacity: Double = 1.0

    private var active: Bool { isConnected || isReconnecting }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.white : AppColors.grayLabel)
                    .frame(width: 8, height: 8)
                    .opacity(isReconnecting ? dotOpacity : 1.0)
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(active ? Color.white : AppColors.grayLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isReconnecting
                    ? AppColors.reconnecting
                    : (isConnected ? AppColors.success.opacity(rxBlink ? 0.7 : 1.0) : AppColors.pillDisconnected)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onAppear { updateBlink() }
        .onChange(of: isReconnecting) { _ in updateBlink() }
    }

    private func updateBlink() {
        if isReconnecting {
            dotOpacity = 1.0
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                dotOpacity = 0.2
            }
        } else {
            withAnimation(.default) { dotOpacity = 1.0 }
        }
    }
}
