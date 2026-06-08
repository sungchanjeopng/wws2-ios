// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/MainTabScreen.kt

import SwiftUI
import WWS2Core

private let mainOrange = Color(hex: 0xFFA500)

public struct MainTabScreen: View {
    @ObservedObject var vm: AppViewModel

    public var body: some View {
        let devices = vm.state.connectedDevices
        let densUnit = DensityUnit.fromInt(vm.state.densUnit)

        if devices.isEmpty {
            EmptyMainState(densUnit: densUnit, onOpenPairing: { vm.openPairing() })
        } else {
            let activeDevice = devices.first(where: { $0.id == vm.state.activeDeviceId }) ?? devices[0]
            VStack(spacing: 8) {
                DeviceStripBar(
                    devices: devices,
                    selectedDeviceId: vm.state.activeDeviceId,
                    reconnectingIds: vm.state.reconnectingIds,
                    onDeviceTap: { vm.requestConnectDevice($0) },
                    onMoreTap: { vm.openPairing() }
                )
                DeviceCardLarge(
                    device: activeDevice,
                    reading: vm.state.deviceReadings[activeDevice.id],
                    densUnit: densUnit,
                    isReconnecting: vm.state.reconnectingIds.contains(activeDevice.id)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)
        }
    }
}

private struct EmptyMainState: View {
    let densUnit: DensityUnit
    let onOpenPairing: () -> Void
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Text("No device connected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.grayLabel)
                Button(action: onOpenPairing) {
                    Text("Open Pairing")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}

private struct DeviceCardLarge: View {
    let device: ConnectedBleDevice
    let reading: DeviceReading?
    let densUnit: DensityUnit
    var isReconnecting: Bool = false
    var body: some View {
        let isInterface = device.label.hasPrefix("ENV130")
        ZStack(alignment: .topLeading) {
            VStack { Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.white)
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(AppColors.primary, lineWidth: 1.5)
                )
                .shadow(color: AppColors.cardShadow, radius: 4, y: 2)

            // Device label top-left
            HStack(spacing: 8) {
                Circle().fill(isReconnecting ? AppColors.reconnecting : AppColors.success).frame(width: 8, height: 8)
                Text(device.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.darkText)
                    .lineLimit(1)
            }
            .padding(.top, 24)
            .padding(.leading, 28)

            // Centered content
            if isInterface {
                InterfaceCardContent(reading: reading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
            } else {
                DensityCardContent(reading: reading, densUnit: densUnit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
            }
        }
    }
}

private struct DensityCardContent: View {
    let reading: DeviceReading?
    let densUnit: DensityUnit
    var body: some View {
        let valueText: String = {
            if let r = reading { return densUnit.format(raw: r.level) }
            return "--"
        }()
        VStack(spacing: 8) {
            Text("Density(\(densUnit.unitStr))")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppColors.grayLabel)
            Text(valueText)
                .font(.system(size: 120, weight: .heavy))
                .kerning(-5)
                .foregroundStyle(reading == nil ? AppColors.weakText : AppColors.primary)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
    }
}

private struct InterfaceCardContent: View {
    let reading: DeviceReading?
    var body: some View {
        let lightText: String = {
            if let r = reading { return String(format: "%.2f", r.level) }
            return "--"
        }()
        let heavyText: String = {
            if let r = reading, let h = r.heavyLevel { return String(format: "%.2f", h) }
            return "--"
        }()
        VStack(spacing: 16) {
            LevelBlock(
                label: "Light Level",
                valueText: lightText,
                labelColor: AppColors.grayLabel,
                valueColor: AppColors.darkText,
                mColor: AppColors.grayLabel
            )
            LevelBlock(
                label: "Heavy Level",
                valueText: heavyText,
                labelColor: mainOrange,
                valueColor: mainOrange,
                mColor: mainOrange.opacity(0.6)
            )
        }
    }
}

private struct LevelBlock: View {
    let label: String
    let valueText: String
    let labelColor: Color
    let valueColor: Color
    let mColor: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(labelColor)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(valueText)
                    .font(.system(size: 96, weight: .heavy))
                    .kerning(-2)
                    .foregroundStyle(valueColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("m")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(mColor)
            }
        }
    }
}

