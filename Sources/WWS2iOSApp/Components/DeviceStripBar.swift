// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/DeviceStripBar.kt
//
// Horizontal scrollable strip of currently-connected devices, plus a "+" tile
// to open the pairing screen. The selected device is highlighted; tapping
// any other device makes it active.

import SwiftUI
import WWS2Core

public struct DeviceStripBar: View {
    public let devices: [ConnectedBleDevice]
    public let selectedDeviceId: String
    public let reconnectingIds: Set<String>
    public let onDeviceTap: (String) -> Void
    public let onMoreTap: () -> Void

    public init(
        devices: [ConnectedBleDevice],
        selectedDeviceId: String,
        reconnectingIds: Set<String> = [],
        onDeviceTap: @escaping (String) -> Void,
        onMoreTap: @escaping () -> Void
    ) {
        self.devices = devices
        self.selectedDeviceId = selectedDeviceId
        self.reconnectingIds = reconnectingIds
        self.onDeviceTap = onDeviceTap
        self.onMoreTap = onMoreTap
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(devices, id: \.id) { device in
                    let active = device.id == selectedDeviceId
                    Button(action: { onDeviceTap(device.id) }) {
                        HStack(spacing: 6) {
                            // 왼쪽 점 = 연결 상태: 초록(연결) / 주황(재연결 중)
                            Circle()
                                .fill(reconnectingIds.contains(device.id) ? AppColors.reconnecting : AppColors.success)
                                .frame(width: 6, height: 6)
                            Text(device.label)
                                .font(.system(size: 14, weight: active ? .heavy : .semibold))
                                .foregroundStyle(active ? Color.white : AppColors.darkText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(active ? AppColors.primary : AppColors.white)
                        .overlay(
                            Capsule().stroke(
                                active ? Color.clear : AppColors.border,
                                lineWidth: 1
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onMoreTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.grayLabel)
                        .frame(width: 36, height: 36)
                        .background(AppColors.white)
                        .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }
}
