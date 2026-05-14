// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/TrendChart.kt
//
// Density-meter trend chart: density (blue, primary axis left) and
// temperature (red, secondary axis right). Cubic-Bezier smoothed lines
// over time. Y-axis 5-tick labels in DensityUnit / TemperatureUnit format,
// X-axis 5-tick timestamps with vertical grid dashes.
//
// The Compose original additionally supports two-finger pinch-zoom and
// pan + long-press crosshair tooltip via a complex pointerInput state
// machine. Those gestures are TODO on the SwiftUI side — the chart here
// renders the full data range without zoom/pan.

import SwiftUI
import WWS2Core

public struct TrendChart: View {
    public let records: [TrendRecord]
    public let densUnit: Int
    public let tempUnit: Int

    public init(records: [TrendRecord], densUnit: Int = 0, tempUnit: Int = 0) {
        self.records = records
        self.densUnit = densUnit
        self.tempUnit = tempUnit
    }

    public var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }

    private func draw(context ctx: GraphicsContext, size: CGSize) {
        var context = ctx
        let totalW = size.width
        let totalH = size.height
        let dUnit = DensityUnit.fromInt(densUnit)
        let tUnit = TemperatureUnit.fromInt(tempUnit)

        let marginLeft: CGFloat = 54
        let marginRight: CGFloat = 54
        let marginTop: CGFloat = max(38, min(58, totalH * 0.08))
        let marginBottom: CGFloat = max(42, min(58, totalH * 0.09))

        let baseW = totalW - marginLeft - marginRight
        let baseH = totalH - marginTop - marginBottom

        if baseW <= 0 || baseH <= 0 { return }

        if records.isEmpty {
            let resolved = context.resolve(
                Text("No Data").font(.system(size: 16)).foregroundColor(AppColors.grayLabel)
            )
            let m = resolved.measure(in: size)
            context.draw(resolved,
                         at: CGPoint(x: (totalW - m.width) / 2, y: (totalH - m.height) / 2),
                         anchor: .topLeading)
            return
        }

        // Range
        var dstMax = records.first!.dst
        var tempMin = records.first!.temperature
        var tempMax = records.first!.temperature
        for r in records {
            if r.dst > dstMax { dstMax = r.dst }
            if r.temperature < tempMin { tempMin = r.temperature }
            if r.temperature > tempMax { tempMax = r.temperature }
        }
        let dstMin: Double = 0.0
        dstMax = dstMax < 1.0 ? 1.0 : dstMax * 1.2
        tempMin -= 5; tempMax += 5
        let dstSpan = abs(dstMax - dstMin) < 0.001 ? 1.0 : (dstMax - dstMin)
        let tempSpan = abs(tempMax - tempMin) < 0.001 ? 1.0 : (tempMax - tempMin)

        // Sort by time
        let sorted = records.sorted { $0.dateTime < $1.dateTime }
        let timeStart = sorted.first!.dateTime.timeIntervalSince1970
        let timeEnd = sorted.last!.dateTime.timeIntervalSince1970
        let timeSpan: Double = timeEnd > timeStart ? (timeEnd - timeStart) : 1

        // Y-axis titles
        drawText(context: context, size: size,
                 text: "Density(\(dUnit.unitStr))", size: 15, weight: .bold,
                 color: AppColors.primary,
                 origin: CGPoint(x: 0, y: marginTop - 30 - 18))
        let tempTitleText = "Temp(\(tUnit.unitStr))"
        let tempTitleResolved = context.resolve(
            Text(tempTitleText).font(.system(size: 15, weight: .bold)).foregroundColor(AppColors.temperature)
        )
        let tempTitleM = tempTitleResolved.measure(in: size)
        context.draw(tempTitleResolved,
                     at: CGPoint(x: totalW - tempTitleM.width, y: marginTop - 30 - tempTitleM.height),
                     anchor: .topLeading)

        // Y-axis labels (5 ticks each side)
        for i in 0...4 {
            let dVal = dstMax - dstSpan * Double(i) / 4.0
            let label = dUnit.format(raw: dVal)
            let resolved = context.resolve(
                Text(label).font(.system(size: 12)).foregroundColor(AppColors.primary)
            )
            let m = resolved.measure(in: size)
            let y = marginTop + baseH * CGFloat(i) / 4
            context.draw(resolved,
                         at: CGPoint(x: marginLeft - m.width - 4, y: y - m.height / 2),
                         anchor: .topLeading)
        }
        for i in 0...4 {
            let tVal = tempMax - tempSpan * Double(i) / 4.0
            let label = tUnit.format(celsius: tVal)
            let resolved = context.resolve(
                Text(label).font(.system(size: 12)).foregroundColor(AppColors.temperature)
            )
            let m = resolved.measure(in: size)
            let y = marginTop + baseH * CGFloat(i) / 4
            context.draw(resolved,
                         at: CGPoint(x: marginLeft + baseW + 4, y: y - m.height / 2),
                         anchor: .topLeading)
        }

        // Horizontal grid (dashed)
        let dashStyle = StrokeStyle(lineWidth: 1, dash: [8, 6])
        for i in 0...4 {
            let y = marginTop + baseH * CGFloat(i) / 4
            var p = Path()
            p.move(to: CGPoint(x: marginLeft, y: y))
            p.addLine(to: CGPoint(x: marginLeft + baseW, y: y))
            context.stroke(p, with: .color(Color(hex: 0xCCCCCC)), style: dashStyle)
        }

        // X-axis time labels + vertical grid
        let labelCount = min(5, sorted.count)
        if labelCount > 1 {
            let xInset: CGFloat = 20
            let utcCal: Calendar = {
                var c = Calendar(identifier: .gregorian)
                c.timeZone = TimeZone(identifier: "UTC") ?? .current
                return c
            }()
            for i in 0..<labelCount {
                let t = timeStart + timeSpan * Double(i) / Double(labelCount - 1)
                let date = Date(timeIntervalSince1970: t)
                let comps = utcCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                let text = String(format: "%02d:%02d:%02d\n%02d/%02d/%02d",
                                  comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0,
                                  (comps.year ?? 0) % 100, comps.month ?? 0, comps.day ?? 0)
                let resolved = context.resolve(
                    Text(text).font(.system(size: 11)).foregroundColor(AppColors.grayLabel)
                )
                let m = resolved.measure(in: size)
                let rawX = marginLeft + baseW * CGFloat(i) / CGFloat(labelCount - 1)
                let x: CGFloat = (i == 0)            ? rawX + xInset
                              : (i == labelCount - 1) ? rawX - xInset
                              : rawX

                var p = Path()
                p.move(to: CGPoint(x: x, y: marginTop))
                p.addLine(to: CGPoint(x: x, y: marginTop + baseH))
                context.stroke(p, with: .color(Color(hex: 0xCCCCCC)), style: dashStyle)

                let cx = max(marginLeft, min(totalW - marginRight - m.width, x - m.width / 2))
                context.draw(resolved,
                             at: CGPoint(x: cx, y: marginTop + baseH + marginBottom * 0.35),
                             anchor: .topLeading)
            }
        }

        // Plot points
        var densityPoints: [CGPoint] = []
        var tempPoints: [CGPoint] = []
        for r in sorted {
            let t = r.dateTime.timeIntervalSince1970
            let x = marginLeft + baseW * CGFloat((t - timeStart) / timeSpan)
            let dy = marginTop + baseH - CGFloat((r.dst - dstMin) / dstSpan) * baseH
            let ty = marginTop + baseH - CGFloat((r.temperature - tempMin) / tempSpan) * baseH
            densityPoints.append(CGPoint(x: x, y: dy))
            tempPoints.append(CGPoint(x: x, y: ty))
        }

        // Draw within chart area (clipped)
        var clipPath = Path()
        clipPath.addRect(CGRect(x: marginLeft, y: marginTop, width: baseW, height: baseH))
        context.clip(to: clipPath)

        if densityPoints.count >= 2 {
            let path = smoothPath(densityPoints)
            context.stroke(path, with: .color(AppColors.primary),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if tempPoints.count >= 2 {
            let path = smoothPath(tempPoints)
            context.stroke(path, with: .color(AppColors.temperature.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }

    /// Cubic-bezier smoothing — same midpoint-anchor scheme as the Kotlin original.
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        if pts.isEmpty { return p }
        p.move(to: pts[0])
        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let cur = pts[i]
            let cx = (prev.x + cur.x) / 2
            p.addCurve(
                to: cur,
                control1: CGPoint(x: cx, y: prev.y),
                control2: CGPoint(x: cx, y: cur.y)
            )
        }
        return p
    }

    private func drawText(context: GraphicsContext, size: CGSize,
                          text: String, size pt: CGFloat, weight: Font.Weight,
                          color: Color, origin: CGPoint) {
        let resolved = context.resolve(
            Text(text).font(.system(size: pt, weight: weight)).foregroundColor(color)
        )
        context.draw(resolved, at: origin, anchor: .topLeading)
    }
}
