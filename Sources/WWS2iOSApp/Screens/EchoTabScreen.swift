// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/EchoTabScreen.kt

import SwiftUI
import WWS2Core

private let echoOrange = Color(hex: 0xFFA500)

public struct EchoTabScreen: View {
    @ObservedObject var vm: AppViewModel

    public var body: some View {
        let devices = vm.state.connectedDevices
        let isInterface = vm.state.deviceType == .interface_
        let densUnit = DensityUnit.fromInt(vm.state.densUnit)

        if devices.isEmpty {
            EmptyTabState(
                icon: {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColors.weakText)
                },
                title: "Echo",
                desc: "",
                onOpenPairing: { vm.openPairing() }
            )
        } else if isInterface {
            interfaceEchoView(devices: devices)
        } else {
            densityEchoView(devices: devices, densUnit: densUnit)
        }
    }

    @ViewBuilder
    private func interfaceEchoView(devices: [ConnectedBleDevice]) -> some View {
        let ifReading = vm.state.interfaceEchoReading
        VStack(spacing: 8) {
            DeviceStripBar(
                devices: devices,
                selectedDeviceId: vm.state.activeDeviceId,
                onDeviceTap: { vm.requestConnectDevice($0) },
                onMoreTap: { vm.openPairing() }
            )
            EchoModeToggle(
                currentMode: vm.state.echoMode,
                onModeChange: { vm.setEchoMode($0) }
            )
            HStack(spacing: 0) {
                Text("Thr.Light : \(ifReading.map { "\($0.thrLightSet)%" } ?? "--")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Thr.Heavy : \(ifReading.map { "\($0.thrHeavySet)%" } ?? "--")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(echoOrange)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Echo Amp : \(ifReading.map { "\($0.echoAmp)" } ?? "--")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 4)

            InterfaceEchoChart(echo: ifReading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            InterfaceLevelCards(ifReading: ifReading)
        }
        .padding(12)
    }

    @ViewBuilder
    private func densityEchoView(devices: [ConnectedBleDevice], densUnit: DensityUnit) -> some View {
        let reading = vm.state.echoReading
        VStack(spacing: 8) {
            DeviceStripBar(
                devices: devices,
                selectedDeviceId: vm.state.activeDeviceId,
                onDeviceTap: { vm.requestConnectDevice($0) },
                onMoreTap: { vm.openPairing() }
            )

            EchoChart(echo: reading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatRow(items: [
                StatItem(label: "EEA.R",
                         value: reading.map { "\($0.eeaR)" } ?? "--",
                         color: AppColors.primary),
                StatItem(label: "EEA.D",
                         value: reading.map { "\($0.eeaD)" } ?? "--",
                         color: AppColors.darkText),
                StatItem(label: "Density(\(densUnit.unitStr))",
                         value: reading.map { densUnit.format(raw: $0.level) } ?? "--",
                         color: AppColors.primary)
            ])
        }
        .padding(12)
    }
}

private struct EchoModeToggle: View {
    let currentMode: EchoMode
    let onModeChange: (EchoMode) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach([(EchoMode.real, "Real"), (EchoMode.avg, "Avg")], id: \.0) { mode, label in
                let isSelected = currentMode == mode
                Button(action: { onModeChange(mode) }) {
                    Text(label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? .white : AppColors.grayLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? AppColors.primary : AppColors.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
    }
}

private struct InterfaceLevelCards: View {
    let ifReading: InterfaceEchoReading?
    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 2) {
                Text("Light Level")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                Text(ifReading.map { String(format: "%.2f m", $0.lightLevel) } ?? "--")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: AppColors.cardShadow, radius: 2, y: 1)

            VStack(spacing: 2) {
                Text("Heavy Level")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(echoOrange)
                Text(ifReading.map { String(format: "%.2f m", $0.heavyLevel) } ?? "--")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(echoOrange)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
        }
    }
}
