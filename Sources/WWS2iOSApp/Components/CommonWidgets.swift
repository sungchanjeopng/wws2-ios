// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/CommonWidgets.kt
//
// Reusable building blocks shared across most screens:
// CardContainer, StatRow, DeviceCard, SignalBars, FileSelectArea,
// UploadProgressCard, SettingsPanel, StatusInfoPanel, DiagRow, EmptyTabState,
// plus the formatBytes() helper.

import SwiftUI
import WWS2Core

// MARK: - Card container

public struct CardContainer<Content: View>: View {
    private let content: () -> Content
    public init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

// MARK: - Stat row (3-column metric strip)

public struct StatItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let value: String
    public let color: Color
    public init(label: String, value: String, color: Color) {
        self.label = label; self.value = value; self.color = color
    }
}

public struct StatRow: View {
    public let items: [StatItem]
    public init(items: [StatItem]) { self.items = items }
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(-0.2)
                        .foregroundStyle(AppColors.grayLabel)
                    Text(item.value)
                        .font(.system(size: 19, weight: .bold))
                        .kerning(-0.8)
                        .foregroundStyle(item.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                if i < items.count - 1 {
                    Rectangle()
                        .fill(AppColors.background)
                        .frame(width: 1, height: 52)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

// MARK: - Device card (used in PairingScreen)

public struct DeviceCard: View {
    public let name: String
    public let signalLevel: Int
    public var isConnected: Bool = false
    public var isConnecting: Bool = false
    public var isSelected: Bool = false
    public var onTap: () -> Void = {}
    public var onDisconnectTap: (() -> Void)? = nil

    public init(name: String, signalLevel: Int, isConnected: Bool = false,
                isConnecting: Bool = false, isSelected: Bool = false,
                onTap: @escaping () -> Void = {},
                onDisconnectTap: (() -> Void)? = nil) {
        self.name = name; self.signalLevel = signalLevel
        self.isConnected = isConnected; self.isConnecting = isConnecting
        self.isSelected = isSelected
        self.onTap = onTap; self.onDisconnectTap = onDisconnectTap
    }

    public var body: some View {
        Button(action: { if !isConnecting { onTap() } }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isConnected ? AppColors.success.opacity(0.08) : AppColors.background)
                        .frame(width: 36, height: 36)
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isConnected ? AppColors.success : AppColors.grayLabel)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.darkText)
                        .lineLimit(1)
                    SignalBars(level: signalLevel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    let badgeText = isConnected ? "Connected" : "Disconnected"
                    let badgeBg = isConnected ? AppColors.success.opacity(0.1) : AppColors.background
                    let badgeFg = isConnected ? AppColors.success : AppColors.grayLabel
                    Text(badgeText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(badgeFg)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(badgeBg)
                        .clipShape(Capsule())
                    if isConnected, let onX = onDisconnectTap {
                        Button(action: onX) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppColors.grayLabel)
                                .frame(width: 26, height: 26)
                                .background(AppColors.background)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? AppColors.primary.opacity(0.08) : AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.primary : AppColors.white, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Signal bars (3 bars indicator)

public struct SignalBars: View {
    public let level: Int
    public init(level: Int) { self.level = level }
    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i < level ? AppColors.primary : AppColors.border)
                    .frame(width: 6, height: CGFloat(3 + i * 2))
            }
        }
    }
}

// MARK: - File select area (UploadScreen, DataDownload)

public struct FileSelectArea: View {
    public let onTap: () -> Void
    public init(onTap: @escaping () -> Void) { self.onTap = onTap }
    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.background)
                        .frame(width: 40, height: 40)
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                }
                Text("Open")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppColors.border, lineWidth: 1.5)
            )
            .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Upload progress card

public struct UploadProgressCard: View {
    public let fileName: String
    public let fileSize: Int
    public let progress: Double
    public let isDone: Bool
    public var elapsed: Int64? = nil

    public init(fileName: String, fileSize: Int, progress: Double, isDone: Bool, elapsed: Int64? = nil) {
        self.fileName = fileName; self.fileSize = fileSize
        self.progress = progress; self.isDone = isDone
        self.elapsed = elapsed
    }

    public var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text(fileName)
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.5)
                    .foregroundStyle(AppColors.darkText)
                Spacer().frame(height: 4)
                Text(formatBytes(fileSize))
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.grayLabel)
                Spacer().frame(height: 14)

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(isDone ? AppColors.success : AppColors.primary)
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer().frame(height: 8)
                HStack {
                    Text(isDone ? "Upload Complete" : "Uploading...")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.grayLabel)
                    Spacer()
                    HStack(spacing: 3) {
                        if let e = elapsed {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.grayLabel)
                            let m = e / 60000
                            let s = (e / 1000) % 60
                            Text(String(format: "%02d:%02d", m, s))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.grayLabel)
                            Spacer().frame(width: 10)
                        }
                        Text(String(format: "%.1f%%", progress * 100))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isDone ? AppColors.success : AppColors.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Settings & Status panels (DiagnosticsTabScreen)

public struct SettingsPanel: View {
    public let deviceLabel: String
    public let damping: Int
    public let set4mA: Double
    public let set20mA: Double
    public let pipeDia: Int
    public let freqMHz: Double
    public var densUnit: Int = 0

    public init(deviceLabel: String, damping: Int, set4mA: Double, set20mA: Double,
                pipeDia: Int, freqMHz: Double, densUnit: Int = 0) {
        self.deviceLabel = deviceLabel; self.damping = damping
        self.set4mA = set4mA; self.set20mA = set20mA
        self.pipeDia = pipeDia; self.freqMHz = freqMHz; self.densUnit = densUnit
    }

    public var body: some View {
        let dUnit = DensityUnit.fromInt(densUnit)
        let pipeDiaLabel: String = {
            switch pipeDia {
            case 0: return "0~200 mm"
            case 1: return "200~400 mm"
            case 2: return "400~600 mm"
            default: return "--"
            }
        }()

        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            DiagRow(label: "Damping", value: "\(damping)")
            DiagRow(label: "4mA Set (\(dUnit.unitStr))", value: dUnit.format(raw: set4mA))
            DiagRow(label: "20mA Set (\(dUnit.unitStr))", value: dUnit.format(raw: set20mA))
            DiagRow(label: "PipeDia", value: pipeDiaLabel)
            DiagRow(label: "Freq (MHz)", value: String(format: "%.3f", freqMHz))
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

public struct StatusInfoPanel: View {
    public let currentMA: Double
    public let temperature: Double
    public var tempUnit: Int = 0
    public var relay: Int = 0
    public var extIn1En: Int = 0
    public var extIn1State: Int = 0
    public var extIn2En: Int = 0
    public var extIn2State: Int = 0

    public init(currentMA: Double, temperature: Double, tempUnit: Int = 0, relay: Int = 0,
                extIn1En: Int = 0, extIn1State: Int = 0, extIn2En: Int = 0, extIn2State: Int = 0) {
        self.currentMA = currentMA; self.temperature = temperature
        self.tempUnit = tempUnit; self.relay = relay
        self.extIn1En = extIn1En; self.extIn1State = extIn1State
        self.extIn2En = extIn2En; self.extIn2State = extIn2State
    }

    public var body: some View {
        let tUnit = TemperatureUnit.fromInt(tempUnit)
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            DiagRow(label: "Current (mA)", value: String(format: "%.2f", currentMA))
            DiagRow(label: "Temp (\(tUnit.unitStr))", value: tUnit.format(celsius: temperature))
            DiagRow(label: "Relay", value: relay == 1 ? "Act" : "Stop")
            ExtInputRow(label: "Ext. IN 1", en: extIn1En, state: extIn1State)
            ExtInputRow(label: "Ext. IN 2", en: extIn2En, state: extIn2State)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

/// LCD vw_param.c rule:
///   en=0       → "OFF" (gray, disabled)
///   en=1, s=ON → "ON (HIGH)"
///   en=1, else → "ON (LOW)"
private struct ExtInputRow: View {
    let label: String
    let en: Int
    let state: Int
    private let extStateOn = 2
    var body: some View {
        if en == 0 {
            HStack {
                Text(label)
                    .font(.system(size: 19))
                    .foregroundStyle(AppColors.weakText)
                Spacer()
                Text("OFF")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.weakText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else {
            DiagRow(label: label, value: state == extStateOn ? "ON (HIGH)" : "ON (LOW)")
        }
    }
}

public struct DiagRow: View {
    public let label: String
    public let value: String
    public init(label: String, value: String) { self.label = label; self.value = value }
    public var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 19))
                .foregroundStyle(AppColors.grayLabel)
            Spacer()
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.darkText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Empty-state placeholder (used by tab screens with no device)

public struct EmptyTabState<Icon: View>: View {
    public let icon: () -> Icon
    public let title: String
    public let desc: String
    public let onOpenPairing: () -> Void

    public init(@ViewBuilder icon: @escaping () -> Icon,
                title: String, desc: String,
                onOpenPairing: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.desc = desc
        self.onOpenPairing = onOpenPairing
    }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            icon()
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.darkText)
            if !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)
            }
            Button(action: onOpenPairing) {
                Text("Connect a device")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

// MARK: - formatBytes

public func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
    return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
}
