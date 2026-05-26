// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/DiagnosticsTabScreen.kt

import SwiftUI
import WWS2Core

public struct DiagnosticsTabScreen: View {
    @ObservedObject var vm: AppViewModel

    public var body: some View {
        let devices = vm.state.connectedDevices
        if devices.isEmpty {
            EmptyTabState(
                icon: {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColors.weakText)
                },
                title: "Parameter",
                desc: "",
                onOpenPairing: { vm.openPairing() }
            )
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    DeviceStripBar(
                        devices: devices,
                        selectedDeviceId: vm.state.activeDeviceId,
                        onDeviceTap: { vm.requestConnectDevice($0) },
                        onMoreTap: { vm.openPairing() }
                    )

                    if vm.state.deviceType == .interface_ {
                        InterfaceParametersPanel(state: vm.state)
                        InterfaceStatusPanel(state: vm.state)
                    } else {
                        SettingsPanel(
                            deviceLabel: vm.isConnected ? vm.state.activeDeviceLabel : "--",
                            damping: vm.state.damping,
                            set4mA: vm.state.set4mA,
                            set20mA: vm.state.set20mA,
                            pipeDia: vm.state.pipeDia,
                            freqMHz: vm.state.freqMHz,
                            densUnit: vm.state.densUnit
                        )
                        StatusInfoPanel(
                            currentMA: vm.state.currentMA,
                            temperature: vm.state.temperatureC,
                            tempUnit: vm.state.tempUnit,
                            relay: vm.state.relay,
                            extIn1En: vm.state.extIn1En,
                            extIn1State: vm.state.extIn1State,
                            extIn2En: vm.state.extIn2En,
                            extIn2State: vm.state.extIn2State
                        )
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct InterfaceParametersPanel: View {
    let state: MainUiState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            DiagRow(label: "Freq",     value: "\(Int((state.freqMHz * 1000).rounded())) kHz")
            DiagRow(label: "Offset",   value: String(format: "%.2f m", state.offset))
            DiagRow(label: "4mA Set",  value: String(format: "%.2f", state.set4mA))
            DiagRow(label: "20mA Set", value: String(format: "%.2f", state.set20mA))
            DiagRow(label: "TVG",      value: "\(state.tvg)")
            DiagRow(label: "Damping",  value: "\(state.damping)")
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

private struct InterfaceStatusPanel: View {
    let state: MainUiState
    var body: some View {
        let tUnit = TemperatureUnit.fromInt(state.tempUnit)
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            DiagRow(label: "Temperature",
                    value: "\(tUnit.format(celsius: state.temperatureC)) \(tUnit.unitStr)")
            DiagRow(label: "Current",
                    value: String(format: "%.2f mA", state.currentMA))
            DiagRow(label: "Relay",
                    value: state.relay == 1 ? "Act" : "Stop")
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}
