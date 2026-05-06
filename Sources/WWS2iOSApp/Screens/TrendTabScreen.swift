// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/TrendTabScreen.kt

import SwiftUI
import WWS2Core

public struct TrendTabScreen: View {
    @ObservedObject var vm: AppViewModel

    public var body: some View {
        let devices = vm.state.connectedDevices
        let isInterface = vm.state.deviceType == .interface_
        let activeId = vm.state.activeDeviceId
        let records = vm.state.trendRecords.filter { $0.deviceId == activeId }
        let valueLabel = isInterface ? "Light" : "Density"

        if devices.isEmpty {
            EmptyTabState(
                icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColors.weakText)
                },
                title: "Trend",
                desc: "",
                onOpenPairing: { vm.openPairing() }
            )
        } else {
            VStack(spacing: 8) {
                DeviceStripBar(
                    devices: devices,
                    selectedDeviceId: activeId,
                    onDeviceTap: { vm.requestConnectDevice($0) },
                    onMoreTap: { vm.openPairing() }
                )

                chartArea(isInterface: isInterface, records: records)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                statsArea(isInterface: isInterface, records: records, valueLabel: valueLabel)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func chartArea(isInterface: Bool, records: [TrendRecord]) -> some View {
        if let err = vm.state.trendError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(hex: 0xE53935))
                Text("Transfer Failed")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Text(err)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.state.isTrendStreaming {
            let total = vm.state.trendExpectedRecords
            let progress = total > 0 ? min(Double(records.count) / Double(total), 1.0) : 0
            let percent = Int(progress * 100)
            VStack(spacing: 24) {
                Text("Loading trend data...")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColors.grayLabel)
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(AppColors.primary)
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 32)
                Text("\(percent)%  (\(records.count) / \(total))")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isInterface {
            InterfaceTrendChart(records: records, tempUnit: vm.state.tempUnit)
        } else {
            TrendChart(records: records, densUnit: vm.state.densUnit, tempUnit: vm.state.tempUnit)
        }
    }

    @ViewBuilder
    private func statsArea(isInterface: Bool, records: [TrendRecord], valueLabel: String) -> some View {
        if isInterface {
            let lightStats = interfaceStats(records: records, isLight: true)
            let heavyStats = interfaceStats(records: records, isLight: false)
            InterfaceStatCard(lightStats: lightStats, heavyStats: heavyStats)
        } else {
            let dUnit = DensityUnit.fromInt(vm.state.densUnit)
            let stats = trendStats(records: records, dUnit: dUnit)
            StatRow(items: [
                StatItem(label: "\(valueLabel) Min", value: stats.min, color: AppColors.primary),
                StatItem(label: "\(valueLabel) Avg", value: stats.avg, color: AppColors.darkText),
                StatItem(label: "\(valueLabel) Max", value: stats.max, color: AppColors.temperature)
            ])
        }
    }
}

// MARK: - Stats helpers

private struct TripleStats { let min, avg, max: String }

private func trendStats(records: [TrendRecord], dUnit: DensityUnit) -> TripleStats {
    if records.isEmpty { return TripleStats(min: "--", avg: "--", max: "--") }
    var minV = records.first!.dst
    var maxV = records.first!.dst
    var sum = 0.0
    for r in records {
        if r.dst < minV { minV = r.dst }
        if r.dst > maxV { maxV = r.dst }
        sum += r.dst
    }
    let avg = sum / Double(records.count)
    return TripleStats(min: dUnit.format(raw: minV),
                       avg: dUnit.format(raw: avg),
                       max: dUnit.format(raw: maxV))
}

private struct IfStats { let min, max, avg: String }

private func interfaceStats(records: [TrendRecord], isLight: Bool) -> IfStats {
    if records.isEmpty { return IfStats(min: "--", max: "--", avg: "--") }
    let values = isLight
        ? records.map { $0.dst * 0.01 }
        : records.map { Double($0.eeaD) * 0.01 }
    let mn = values.min() ?? 0
    let mx = values.max() ?? 0
    let avg = values.reduce(0, +) / Double(values.count)
    return IfStats(min: String(format: "%.2f", mn),
                   max: String(format: "%.2f", mx),
                   avg: String(format: "%.2f", avg))
}

private let trendOrange = Color(hex: 0xFFA500)
private let trendGray   = Color(hex: 0x666666)

private struct InterfaceStatCard: View {
    let lightStats: IfStats
    let heavyStats: IfStats
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatCell(label: "Light Level (Min)", value: lightStats.min, color: trendGray)
                StatCell(label: "Light Level (Max)", value: lightStats.max, color: trendGray)
                StatCell(label: "Light Level (Avg)", value: lightStats.avg, color: trendGray)
            }
            Rectangle()
                .fill(AppColors.background)
                .frame(height: 1)
                .padding(.horizontal, 12)
            HStack(spacing: 0) {
                StatCell(label: "Heavy Level (Min)", value: heavyStats.min, color: trendOrange)
                StatCell(label: "Heavy Level (Max)", value: heavyStats.max, color: trendOrange)
                StatCell(label: "Heavy Level (Avg)", value: heavyStats.avg, color: trendOrange)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.grayLabel)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
