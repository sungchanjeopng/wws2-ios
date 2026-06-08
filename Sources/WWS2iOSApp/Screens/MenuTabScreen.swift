// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/MenuTabScreen.kt

import SwiftUI
import WWS2Core

public struct MenuTabScreen: View {
    @ObservedObject var vm: AppViewModel

    public var body: some View {
        let isInterface = vm.state.deviceType == .interface_
        ScrollView {
            VStack(spacing: 10) {
                if !vm.state.connectedDevices.isEmpty {
                    DeviceStripBar(
                        devices: vm.state.connectedDevices,
                        selectedDeviceId: vm.state.activeDeviceId,
                        reconnectingIds: vm.state.reconnectingIds,
                        onDeviceTap: { vm.requestConnectDevice($0) },
                        onMoreTap: { vm.openPairing() }
                    )
                    .padding(.bottom, 2)
                }

                MenuCard(
                    systemIcon: "wave.3.right.circle.fill",
                    iconBg: Color(hex: 0xE8F3FF),
                    iconColor: AppColors.primary,
                    title: "Pairing",
                    trailing: {
                        AnyView(
                            Group {
                                if vm.isConnected { ConnectedBadge() } else { EmptyView() }
                            }
                        )
                    },
                    onTap: { vm.openPairing() }
                )

                MenuCard(
                    systemIcon: "doc.text.fill",
                    iconBg: Color(hex: 0xE8F3FF),
                    iconColor: AppColors.primary,
                    title: "Data Files",
                    trailing: { AnyView(EmptyView()) },
                    onTap: { vm.openDataFilesList() }
                )

                MenuCard(
                    systemIcon: "icloud.and.arrow.up.fill",
                    iconBg: Color(hex: 0xE6F9F1),
                    iconColor: AppColors.success,
                    title: "Firmware Upload",
                    trailing: { AnyView(EmptyView()) },
                    onTap: { vm.openFirmwareFlow() }
                )

                if !isInterface {
                    MenuCard(
                        systemIcon: "slider.horizontal.3",
                        iconBg: Color(hex: 0xFFF3E0),
                        iconColor: Color(hex: 0xF57C00),
                        title: "Calibration",
                        trailing: { AnyView(EmptyView()) },
                        onTap: { vm.openCalib() }
                    )
                }

                Text("App Version 1.0.0")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.weakText)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct MenuCard: View {
    let systemIcon: String
    let iconBg: Color
    let iconColor: Color
    let title: String
    let trailing: () -> AnyView
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                trailing()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.grayLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct ConnectedBadge: View {
    var body: some View {
        Text("Connected")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppColors.success)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(hex: 0xE6F9F1))
            .clipShape(Capsule())
    }
}
