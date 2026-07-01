// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/DiagnosticsTabScreen.kt

import SwiftUI
import WWS2Core

// MARK: - Edit descriptor (mirrors Kotlin ConfigEdit data class)

/// Describes a single editable parameter. The struct is value-typed and used
/// only inside this screen, so `Identifiable` lets us drive a SwiftUI `.sheet`
/// off the optional state. Equatable so SwiftUI can diff during the animation.
struct ConfigEdit: Identifiable, Equatable {
    let id = UUID()
    let title: String
    /// Base command code (without _CH2 offset — the ViewModel adds +1000 when needed).
    let cmd: Int
    let value: Int
    let min: Int
    let max: Int
    let step: Int
    let allowTextInput: Bool
    /// 1 = integer-only, 100 = two decimal digits (raw is value × 100).
    let decimalScale: Int
    /// Optional finite set for enum-like values. Used to skip legacy/reserved values.
    let allowedValues: [Int]?
    let formatter: (Int) -> String

    init(title: String, cmd: Int, value: Int, min: Int, max: Int, step: Int,
         allowTextInput: Bool = true, decimalScale: Int = 1, allowedValues: [Int]? = nil,
         formatter: @escaping (Int) -> String) {
        self.title = title
        self.cmd = cmd
        self.value = value
        self.min = min
        self.max = max
        self.step = step
        self.allowTextInput = allowTextInput
        self.decimalScale = decimalScale
        self.allowedValues = allowedValues
        self.formatter = formatter
    }

    static func == (lhs: ConfigEdit, rhs: ConfigEdit) -> Bool {
        lhs.id == rhs.id
    }
}

public struct DiagnosticsTabScreen: View {
    @ObservedObject var vm: AppViewModel
    @State private var edit: ConfigEdit? = nil

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
                        reconnectingIds: vm.state.reconnectingIds,
                        onDeviceTap: { vm.requestConnectDevice($0) },
                        onMoreTap: { vm.openPairing() }
                    )

                    if vm.state.deviceType == .interface_ {
                        InterfaceParametersPanel(state: vm.state, onEdit: { edit = $0 })
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
            .sheet(item: $edit) { cfg in
                ConfigEditSheet(
                    config: cfg,
                    onApply: { value in
                        await vm.sendAppSetting(baseCmd: cfg.cmd, value: value)
                    },
                    onCancel: { edit = nil }
                )
                .presentationDetents([.medium])
            }
        }
    }
}

private struct InterfaceParametersPanel: View {
    let state: MainUiState
    let onEdit: (ConfigEdit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)

            // Freq — picker-style. 1 is legacy/reserved 270 kHz, so skip it for new selections.
            EditableDiagRow(label: "Freq",
                            value: String(format: "%d kHz", Int((state.freqMHz * 1000).rounded()))) {
                let kHz = Int((state.freqMHz * 1000).rounded())
                let current: Int = {
                    switch kHz {
                    case 380: return 0
                    case 160: return 2
                    case 130: return 3
                    case 415: return 4
                    default:  return 4
                    }
                }()
                onEdit(ConfigEdit(title: "Frequency", cmd: 6, value: current,
                                  min: 0, max: 4, step: 1, allowTextInput: false,
                                  allowedValues: [0, 2, 3, 4]) { v in
                    switch v {
                    case 0: return "380 kHz"
                    case 2: return "160 kHz"
                    case 3: return "130 kHz"
                    case 4: return "415 kHz"
                    default: return "--"
                    }
                })
            }

            EditableDiagRow(label: "Offset",
                            value: String(format: "%.2f m", state.offset)) {
                onEdit(ConfigEdit(title: "Offset", cmd: 7,
                                  value: Int((state.offset * 100).rounded()),
                                  min: -100, max: 100, step: 1, decimalScale: 100) { v in
                    String(format: "%.2f m", Double(v) / 100.0)
                })
            }

            EditableDiagRow(label: "Empty",
                            value: String(format: "%.2f m", state.emptyDistance)) {
                onEdit(ConfigEdit(title: "Empty", cmd: 12,
                                  value: Int((state.emptyDistance * 100).rounded()),
                                  min: 1, max: 1000, step: 1, decimalScale: 100) { v in
                    String(format: "%.2f m", Double(v) / 100.0)
                })
            }

            EditableDiagRow(label: "Dead Zone",
                            value: String(format: "%.2f m", state.deadZone)) {
                onEdit(ConfigEdit(title: "Dead Zone", cmd: 13,
                                  value: Int((state.deadZone * 100).rounded()),
                                  min: 35, max: 1000, step: 1, decimalScale: 100) { v in
                    String(format: "%.2f m", Double(v) / 100.0)
                })
            }

            EditableDiagRow(label: "4mA Set",
                            value: String(format: "%.2f", state.set4mA)) {
                onEdit(ConfigEdit(title: "4mA Set", cmd: 8,
                                  value: Int((state.set4mA * 100).rounded()),
                                  min: 0, max: 1000, step: 1, decimalScale: 100) { v in
                    String(format: "%.2f", Double(v) / 100.0)
                })
            }

            EditableDiagRow(label: "20mA Set",
                            value: String(format: "%.2f", state.set20mA)) {
                onEdit(ConfigEdit(title: "20mA Set", cmd: 9,
                                  value: Int((state.set20mA * 100).rounded()),
                                  min: 0, max: 1000, step: 1, decimalScale: 100) { v in
                    String(format: "%.2f", Double(v) / 100.0)
                })
            }

            EditableDiagRow(label: "Damping", value: "\(state.damping)") {
                onEdit(ConfigEdit(title: "Damping", cmd: 11, value: state.damping,
                                  min: 1, max: 100, step: 1) { v in "\(v)" })
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

private struct EditableDiagRow: View {
    let label: String
    let value: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 19))
                    .foregroundStyle(AppColors.grayLabel)
                Spacer()
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.darkText)
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.weakText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

// MARK: - ConfigEditSheet — mirrors Kotlin ConfigEditDialog (lines 168-275)

/// Mirrors Kotlin `ConfigEditDialog` behaviour:
///   - "-" / "+" buttons step by `config.step`
///   - When `allowTextInput == true`:
///       - `decimalScale > 1`: integer / fraction text fields side-by-side
///       - else: single integer text field
///   - "Apply" is disabled when the parsed value falls outside [min, max]
///   - "Cancel" dismisses without writing
private enum DiagSendingState { case idle, sending, done, failed }

struct ConfigEditSheet: View {
    let config: ConfigEdit
    let onApply: (Int) async -> Bool
    let onCancel: () -> Void

    @State private var stepperValue: Int
    @State private var intText: String
    @State private var fracText: String
    @State private var sendingState: DiagSendingState = .idle

    init(config: ConfigEdit, onApply: @escaping (Int) async -> Bool, onCancel: @escaping () -> Void) {
        self.config = config
        self.onApply = onApply
        self.onCancel = onCancel
        let clamped = Self.normalizeAllowed(config.value, min: config.min, max: config.max,
                                            allowedValues: config.allowedValues)
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
        let absRaw = abs(raw)
        let frac = absRaw % scale
        // pad to 2 digits when scale == 100 (matches Kotlin padStart(2,'0'))
        return String(format: "%02d", frac)
    }

    private static func normalizeAllowed(_ raw: Int, min: Int, max: Int,
                                         allowedValues: [Int]?, reference: Int? = nil) -> Int {
        let bounded = Swift.min(Swift.max(raw, min), max)
        guard let allowedValues else { return bounded }
        let allowed = allowedValues.filter { $0 >= min && $0 <= max }.sorted()
        guard !allowed.isEmpty else { return bounded }
        if allowed.contains(bounded) { return bounded }
        let pivot = reference ?? bounded
        if raw > pivot {
            return allowed.first(where: { $0 > pivot }) ?? allowed.first!
        }
        if raw < pivot {
            return allowed.last(where: { $0 < pivot }) ?? allowed.last!
        }
        return allowed.min(by: { abs($0 - bounded) < abs($1 - bounded) }) ?? allowed.first!
    }

    private func parseRaw() -> Int? {
        if config.decimalScale <= 1 {
            return Int(intText)
        }
        guard let intPart  = Int(intText) else { return nil }
        guard let fracPart = Int(fracText) else { return nil }
        guard fracPart >= 0 && fracPart < config.decimalScale else { return nil }
        let negative = intText.trimmingCharacters(in: .whitespaces).hasPrefix("-")
        let rawAbs = abs(intPart) * config.decimalScale + fracPart
        return negative ? -rawAbs : rawAbs
    }

    private var parsedValue: Int? {
        let raw = config.allowTextInput ? parseRaw() : stepperValue
        guard let r = raw else { return nil }
        guard r >= config.min && r <= config.max else { return nil }
        if let allowed = config.allowedValues, !allowed.contains(r) { return nil }
        return r
    }

    private func setValue(_ newValue: Int) {
        let clamped = Self.normalizeAllowed(newValue, min: config.min, max: config.max,
                                            allowedValues: config.allowedValues,
                                            reference: stepperValue)
        stepperValue = clamped
        intText  = Self.integerText(raw: clamped, scale: config.decimalScale)
        fracText = Self.fractionText(raw: clamped, scale: config.decimalScale)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(config.title)
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 20)

            // Stepper row: [-]  formatted value  [+]
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

            // Text-input row (only when allowTextInput == true)
            if config.allowTextInput {
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
                        Text("Range \(config.formatter(config.min)) ~ \(config.formatter(config.max))")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.grayLabel)
                    }
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            // Action buttons (state-driven)
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

    /// Matches Kotlin `input.text.filterIndexed { idx, ch -> ch.isDigit() ||
    /// (ch == '-' && idx == 0 && config.min < 0) }`.
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
