// Temporary chart placeholders. The real implementations port the Compose
// Canvas drawing in TrendChart.kt (374 lines), InterfaceTrendChart.kt (392),
// EchoChart.kt (324), and InterfaceEchoChart.kt (165). Each placeholder
// shows the data shape it will plot (record count / sample count) so the
// surrounding screens can build and lay out correctly until the canvas
// drawing code is filled in.

import SwiftUI
import WWS2Core

public struct TrendChart: View {
    public let records: [TrendRecord]
    public let densUnit: Int
    public let tempUnit: Int
    public init(records: [TrendRecord], densUnit: Int, tempUnit: Int) {
        self.records = records; self.densUnit = densUnit; self.tempUnit = tempUnit
    }
    public var body: some View {
        ChartPlaceholderBody(title: "Trend Chart", subtitle: "\(records.count) records",
                             srcFile: "TrendChart.kt (374 lines)")
    }
}

public struct InterfaceTrendChart: View {
    public let records: [TrendRecord]
    public let tempUnit: Int
    public init(records: [TrendRecord], tempUnit: Int) {
        self.records = records; self.tempUnit = tempUnit
    }
    public var body: some View {
        ChartPlaceholderBody(title: "Interface Trend Chart", subtitle: "\(records.count) records",
                             srcFile: "InterfaceTrendChart.kt (392 lines)")
    }
}

public struct EchoChart: View {
    public let echo: EchoReading?
    public init(echo: EchoReading?) { self.echo = echo }
    public var body: some View {
        let n = echo?.wave.count ?? 0
        ChartPlaceholderBody(title: "Echo Chart", subtitle: "\(n) wave samples",
                             srcFile: "EchoChart.kt (324 lines)")
    }
}

public struct InterfaceEchoChart: View {
    public let echo: InterfaceEchoReading?
    public init(echo: InterfaceEchoReading?) { self.echo = echo }
    public var body: some View {
        let n = echo?.wave.count ?? 0
        ChartPlaceholderBody(title: "Interface Echo Chart", subtitle: "\(n) wave samples",
                             srcFile: "InterfaceEchoChart.kt (165 lines)")
    }
}

private struct ChartPlaceholderBody: View {
    let title: String
    let subtitle: String
    let srcFile: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.white)
                .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
            VStack(spacing: 6) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.weakText)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.grayLabel)
                Text("// TODO: port \(srcFile)")
                    .font(.caption)
                    .foregroundStyle(AppColors.weakText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
