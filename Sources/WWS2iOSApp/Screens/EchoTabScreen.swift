// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/EchoTabScreen.kt

import SwiftUI
import WWS2Core

private let echoOrange = Color(hex: 0xFFA500)
private let echoDzEmpty = Color(hex: 0x3182F6)

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
    /// 1 = integer-only, 100 = two decimal digits (raw is value × 100).
    var decimalScale: Int = 1
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
            EchoEditSheet(
                config: cfg,
                onApply: { value in
                    await vm.sendAppSetting(baseCmd: cfg.cmd, value: value)
                },
                onCancel: { edit = nil }
            )
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
                reconnectingIds: vm.state.reconnectingIds,
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
                reconnectingIds: vm.state.reconnectingIds,
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
// Five editable cells: Thr.Light, Thr.Heavy, Echo Amp, Empty, Dead Zone.
// Too wide for one screen → horizontal scroll (first three visible initially).

private struct EchoRowScrollInfo: Equatable {
    var contentMinX: CGFloat = 0
    var contentMaxX: CGFloat = 0
    var containerWidth: CGFloat = 0
}

private struct EchoRowScrollInfoKey: PreferenceKey {
    static var defaultValue = EchoRowScrollInfo()
    static func reduce(value: inout EchoRowScrollInfo, nextValue: () -> EchoRowScrollInfo) {
        let next = nextValue()
        if next.containerWidth != 0 {
            value.containerWidth = next.containerWidth
        } else {
            value.contentMinX = next.contentMinX
            value.contentMaxX = next.contentMaxX
        }
    }
}

private struct InterfaceEchoInfoRow: View {
    let ifReading: InterfaceEchoReading?
    let onEdit: (EchoEdit) -> Void

    @State private var canScrollLeft = false
    @State private var canScrollRight = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
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
                alignment: .leading
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
                alignment: .leading
            ) {
                let cur = ifReading?.echoAmp ?? 15
                onEdit(EchoEdit(title: "Echo Amp", cmd: 1, value: cur,
                                min: 1, max: 50, step: 1,
                                formatter: { v in "\(v)" }))
            }

            EditableEchoInfo(
                text: "Empty  " + (ifReading.map { String(format: "%.2fm", Double($0.empty) * 0.01) } ?? "--"),
                color: echoDzEmpty,
                alignment: .leading
            ) {
                guard let r = ifReading else { return }
                onEdit(EchoEdit(title: "Empty", cmd: 12, value: r.empty,
                                min: 1, max: 1000, step: 1, decimalScale: 100,
                                formatter: { v in String(format: "%.2f m", Double(v) / 100.0) }))
            }

            EditableEchoInfo(
                text: "Dead Zone  " + (ifReading.map { String(format: "%.2fm", Double($0.deadzone) * 0.01) } ?? "--"),
                color: echoDzEmpty,
                alignment: .leading
            ) {
                guard let r = ifReading else { return }
                onEdit(EchoEdit(title: "Dead Zone", cmd: 13, value: r.deadzone,
                                min: 35, max: 1000, step: 1, decimalScale: 100,
                                formatter: { v in String(format: "%.2f m", Double(v) / 100.0) }))
            }
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: EchoRowScrollInfoKey.self,
                        value: EchoRowScrollInfo(
                            contentMinX: geo.frame(in: .named("echoInfoRow")).minX,
                            contentMaxX: geo.frame(in: .named("echoInfoRow")).maxX,
                            containerWidth: 0
                        )
                    )
                }
            )
        }
        .coordinateSpace(name: "echoInfoRow")
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: EchoRowScrollInfoKey.self,
                    value: EchoRowScrollInfo(contentMinX: 0, contentMaxX: 0, containerWidth: geo.size.width)
                )
            }
        )
        .onPreferenceChange(EchoRowScrollInfoKey.self) { info in
            canScrollLeft = info.contentMinX < -2
            canScrollRight = info.contentMaxX > info.containerWidth + 2
        }
        .overlay(alignment: .leading) {
            if canScrollLeft { edgeFade(leading: true) }
        }
        .overlay(alignment: .trailing) {
            if canScrollRight { edgeFade(leading: false) }
        }
    }

    private func edgeFade(leading: Bool) -> some View {
        HStack(spacing: 0) {
            if leading {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.grayLabel)
                    .frame(maxHeight: .infinity)
                    .background(AppColors.background)
                LinearGradient(colors: [AppColors.background, AppColors.background.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
            } else {
                LinearGradient(colors: [AppColors.background.opacity(0), AppColors.background],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.grayLabel)
                    .frame(maxHeight: .infinity)
                    .background(AppColors.background)
            }
        }
        .allowsHitTesting(false)
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

private enum EchoSendingState { case idle, sending, done, failed }

struct EchoEditSheet: View {
    let config: EchoEdit
    let onApply: (Int) async -> Bool
    let onCancel: () -> Void

    @State private var stepperValue: Int
    @State private var intText: String
    @State private var fracText: String
    @State private var sendingState: EchoSendingState = .idle

    init(config: EchoEdit, onApply: @escaping (Int) async -> Bool, onCancel: @escaping () -> Void) {
        self.config = config
        self.onApply = onApply
        self.onCancel = onCancel
        let clamped = Swift.min(Swift.max(config.value, config.min), config.max)
        _stepperValue = State(initialValue: clamped)
        _intText      = State(initialValue: Self.integerText(raw: clamped, scale: config.decimalScale))
        _fracText     = State(initialValue: Self.fractionText(raw: clamped, scale: config.decimalScale))
    }

    private static func integerText(raw: Int, scale: Int) -> String {
        if scale <= 1 { return "\(raw)" }
        let absRaw = abs(raw)
        let sign = raw < 0 ? "-" : ""
        return sign + "\(absRaw / scale)"
    }

    private static func fractionText(raw: Int, scale: Int) -> String {
        if scale <= 1 { return "" }
        return String(format: "%02d", abs(raw) % scale)
    }

    private func parseRaw() -> Int? {
        if config.decimalScale <= 1 { return Int(intText) }
        guard let intPart  = Int(intText) else { return nil }
        guard let fracPart = Int(fracText) else { return nil }
        guard fracPart >= 0 && fracPart < config.decimalScale else { return nil }
        let negative = intText.trimmingCharacters(in: .whitespaces).hasPrefix("-")
        let rawAbs = abs(intPart) * config.decimalScale + fracPart
        return negative ? -rawAbs : rawAbs
    }

    private var parsedValue: Int? {
        guard let n = parseRaw() else { return nil }
        return (n >= config.min && n <= config.max) ? n : nil
    }

    private func setValue(_ newValue: Int) {
        let clamped = Swift.min(Swift.max(newValue, config.min), config.max)
        stepperValue = clamped
        intText  = Self.integerText(raw: clamped, scale: config.decimalScale)
        fracText = Self.fractionText(raw: clamped, scale: config.decimalScale)
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

            if config.decimalScale > 1 {
                HStack(spacing: 6) {
                    TextField("", text: $intText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 20))
                        .frame(width: 100)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(parsedValue == nil ? AppColors.error : AppColors.weakText,
                                        lineWidth: 1)
                        )
                        .onChange(of: intText) { newValue in
                            let allowMinus = config.min < 0
                            intText = filterIntegerInput(newValue, allowMinus: allowMinus)
                        }

                    Text(".")
                        .font(.system(size: 24, weight: .bold))

                    TextField("", text: $fracText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 20))
                        .frame(width: 80)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(parsedValue == nil ? AppColors.error : AppColors.weakText,
                                        lineWidth: 1)
                        )
                        .onChange(of: fracText) { newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            fracText = String(filtered.prefix(2))
                        }
                }
                .padding(.horizontal, 20)

                Text("Range \(config.formatter(config.min)) ~ \(config.formatter(config.max))")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.grayLabel)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Value", text: $intText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 20))
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(parsedValue == nil ? AppColors.error : AppColors.weakText,
                                        lineWidth: 1)
                        )
                        .onChange(of: intText) { newValue in
                            let allowMinus = config.min < 0
                            intText = filterIntegerInput(newValue, allowMinus: allowMinus)
                        }
                    Text("Range \(config.min) ~ \(config.max) / \(parsedValue.map(config.formatter) ?? "Invalid")")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.grayLabel)
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            Group {
                switch sendingState {
                case .idle:
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
                            guard let v = parsedValue else { return }
                            Task {
                                sendingState = .sending
                                let ok = await onApply(v)
                                sendingState = ok ? .done : .failed
                                if ok {
                                    try? await Task.sleep(nanoseconds: 800_000_000)
                                    onCancel()
                                }
                            }
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
                case .sending:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Sending...")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.darkText)
                    }
                case .done:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AppColors.success)
                        Text("Success")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.success)
                    }
                case .failed:
                    VStack(spacing: 12) {
                        Text("✗ Failed")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.error)
                        Button(action: onCancel) {
                            Text("Close")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppColors.lightGray)
                                .foregroundStyle(AppColors.darkText)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
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
