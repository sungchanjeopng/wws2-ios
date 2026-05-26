// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/EchoTabScreen.kt

import SwiftUI
import WWS2Core

private let echoOrange = Color(hex: 0xFFA500)

// MARK: - Edit descriptor (mirrors Kotlin EchoEdit data class — EchoTabScreen.kt:257-265)

struct EchoEdit: Identifiable, Equatable {
    let id = UUID()
    let title: String
    /// Base command code (no _CH2 offset — ViewModel adds it).
    let cmd: Int
    let value: Int
    let min: Int
    let max: Int
    let step: Int
    let formatter: (Int) -> String

    static func == (lhs: EchoEdit, rhs: EchoEdit) -> Bool { lhs.id == rhs.id }
}

public struct EchoTabScreen: View {
    @ObservedObject var vm: AppViewModel
    @State private var edit: EchoEdit? = nil

    public var body: some View {
        let devices = vm.state.connectedDevices
        let isInterface = vm.state.deviceType == .interface_
        let densUnit = DensityUnit.fromInt(vm.state.densUnit)

        Group {
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
        .sheet(item: $edit) { cfg in
            EchoEditSheet(config: cfg, onApply: { value in
                vm.sendAppSetting(baseCmd: cfg.cmd, value: value)
                edit = nil
            }, onCancel: {
                edit = nil
            })
            .presentationDetents([.medium])
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

            InterfaceEchoInfoRow(ifReading: ifReading, onEdit: { edit = $0 })

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

// MARK: - InterfaceEchoInfoRow (mirrors Kotlin EchoTabScreen.kt:172-220)
//
// Three editable cells: Thr.Light, Thr.Heavy, Echo Amp. Each opens a different
// EchoEdit depending on the current Auto/Manual mode of that threshold (which
// switches both the unit shown — "%" vs "V" — and the cmd/min/max/step).

private struct InterfaceEchoInfoRow: View {
    let ifReading: InterfaceEchoReading?
    let onEdit: (EchoEdit) -> Void

    var body: some View {
        HStack(spacing: 0) {
            EditableEchoInfo(
                text: thrText(label: "Thr.Light", mode: ifReading?.thrLightMode,
                              raw: ifReading?.thrLightSet),
                color: AppColors.grayLabel,
                alignment: .leading
            ) {
                guard let r = ifReading else { return }
                if r.thrLightMode == 1 {
                    onEdit(EchoEdit(title: "Thr.Light Manual", cmd: 4,
                                    value: r.thrLightSet, min: 0, max: 32, step: 1,
                                    formatter: { v in String(format: "%.1fV", Double(v) / 10.0) }))
                } else {
                    onEdit(EchoEdit(title: "Thr.Light Auto", cmd: 2,
                                    value: r.thrLightSet, min: 0, max: 95, step: 5,
                                    formatter: { v in "\(v)%" }))
                }
            }

            EditableEchoInfo(
                text: thrText(label: "Thr.Heavy", mode: ifReading?.thrHeavyMode,
                              raw: ifReading?.thrHeavySet),
                color: echoOrange,
                alignment: .center
            ) {
                guard let r = ifReading else { return }
                if r.thrHeavyMode == 1 {
                    onEdit(EchoEdit(title: "Thr.Heavy Manual", cmd: 5,
                                    value: r.thrHeavySet, min: 0, max: 32, step: 1,
                                    formatter: { v in String(format: "%.1fV", Double(v) / 10.0) }))
                } else {
                    onEdit(EchoEdit(title: "Thr.Heavy Auto", cmd: 3,
                                    value: r.thrHeavySet, min: 0, max: 95, step: 5,
                                    formatter: { v in "\(v)%" }))
                }
            }

            EditableEchoInfo(
                text: "Echo Amp  \(ifReading?.echoAmp.description ?? "--")",
                color: AppColors.primary,
                alignment: .trailing
            ) {
                let cur = ifReading?.echoAmp ?? 15
                onEdit(EchoEdit(title: "Echo Amp", cmd: 1, value: cur,
                                min: 1, max: 50, step: 1,
                                formatter: { v in "\(v)" }))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 4)
    }

    private func thrText(label: String, mode: Int?, raw: Int?) -> String {
        guard let m = mode, let r = raw else { return "\(label)  --" }
        if m == 1 {
            return String(format: "\(label)  %.1fV", Double(r) / 10.0)
        } else {
            return "\(label)  \(r)%"
        }
    }
}

private enum EditAlignment { case leading, center, trailing }

private struct EditableEchoInfo: View {
    let text: String
    let color: Color
    let alignment: EditAlignment
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Text(text)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.weakText)
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - EchoEditSheet (mirrors Kotlin EchoEditDialog — EchoTabScreen.kt:267-309)

struct EchoEditSheet: View {
    let config: EchoEdit
    let onApply: (Int) -> Void
    let onCancel: () -> Void

    @State private var stepperValue: Int
    @State private var text: String

    init(config: EchoEdit, onApply: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.config = config
        self.onApply = onApply
        self.onCancel = onCancel
        let clamped = Swift.min(Swift.max(config.value, config.min), config.max)
        _stepperValue = State(initialValue: clamped)
        _text         = State(initialValue: "\(clamped)")
    }

    private var parsedValue: Int? {
        guard let n = Int(text) else { return nil }
        return (n >= config.min && n <= config.max) ? n : nil
    }

    private func setValue(_ newValue: Int) {
        let clamped = Swift.min(Swift.max(newValue, config.min), config.max)
        stepperValue = clamped
        text = "\(clamped)"
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(config.title)
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 20)

            HStack {
                Button {
                    setValue((parsedValue ?? stepperValue) - config.step)
                } label: {
                    Text("-")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 44)
                        .background(AppColors.primary.opacity(0.1))
                        .foregroundStyle(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Spacer()
                Text(config.formatter(parsedValue ?? stepperValue))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Spacer()

                Button {
                    setValue((parsedValue ?? stepperValue) + config.step)
                } label: {
                    Text("+")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 44)
                        .background(AppColors.primary.opacity(0.1))
                        .foregroundStyle(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Value", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 20))
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(parsedValue == nil ? AppColors.error : AppColors.weakText,
                                    lineWidth: 1)
                    )
                    .onChange(of: text) { newValue in
                        let allowMinus = config.min < 0
                        text = filterIntegerInput(newValue, allowMinus: allowMinus)
                    }
                Text("Range \(config.min) ~ \(config.max) / \(parsedValue.map(config.formatter) ?? "Invalid")")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.grayLabel)
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.lightGray)
                        .foregroundStyle(AppColors.darkText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    if let v = parsedValue { onApply(v) }
                } label: {
                    Text("Apply")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(parsedValue == nil ? AppColors.weakText : AppColors.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(parsedValue == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func filterIntegerInput(_ raw: String, allowMinus: Bool) -> String {
        var result = ""
        for (idx, ch) in raw.enumerated() {
            if ch.isNumber {
                result.append(ch)
            } else if allowMinus && ch == "-" && idx == 0 {
                result.append(ch)
            }
        }
        return result
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
