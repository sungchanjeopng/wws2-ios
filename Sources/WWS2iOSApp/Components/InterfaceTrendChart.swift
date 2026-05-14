// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/InterfaceTrendChart.kt
//
// Interface-meter trend chart: Light (gray), Heavy (orange), Temperature
// (red, thinner) plotted vs time. Y-axis Level(m) on the left (combined
// Light/Heavy range), Y-axis Temperature on the right (in tempUnit).
//
// Like TrendChart this port renders the static chart only — the Compose
// pinch-zoom + pan + crosshair tooltip gestures are TODO.

import SwiftUI
import WWS2Core

private let trCol_Light = Color(hex: 0x666666)
private let trCol_Heavy = Color(hex: 0xFFA500)
private let trCol_Temp  = Color(hex: 0xFF4444)

public struct InterfaceTrendChart: View {
    public let records: [TrendRecord]
    public let tempUnit: Int

    public init(records: [TrendRecord], tempUnit: Int = 0) {
        self.records = records
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

        // Compute combined Light/Heavy range
        var levelMin = Double.greatestFiniteMagnitude
        var levelMax = -Double.greatestFiniteMagnitude
        var tempMin = records.first!.temperature
        var tempMax = records.first!.temperature
        for r in records {
            let light = r.dst * 0.01
            let heavy = Double(r.eeaD) * 0.01
            if light < levelMin { levelMin = light }
            if light > levelMax { levelMax = light }
            if heavy < levelMin { levelMin = heavy }
            if heavy > levelMax { levelMax = heavy }
            if r.temperature < tempMin { tempMin = r.temperature }
            if r.temperature > tempMax { tempMax = r.temperature }
        }
        levelMin = max(levelMin - 0.2, 0)
        levelMax += 0.2
        tempMin -= 5; tempMax += 5
        let levelSpan = abs(levelMax - levelMin) < 0.001 ? 1 : (levelMax - levelMin)
        let tempSpan = abs(tempMax - tempMin) < 0.001 ? 1 : (tempMax - tempMin)

        // Horizontal grid (dashed)
        let dashStyle = StrokeStyle(lineWidth: 1, dash: [8, 6])
        for i in 0...4 {
            let y = marginTop + baseH * CGFloat(i) / 4
            var p = Path()
            p.move(to: CGPoint(x: marginLeft, y: y))
            p.addLine(to: CGPoint(x: marginLeft + baseW, y: y))
            context.stroke(p, with: .color(Color(hex: 0xCCCCCC)), style: dashStyle)
        }

        // Y-axis titles
        let titleGap = max(8, min(30, marginTop * 0.27))
        let levelTitle = context.resolve(
            Text("Level(m)").font(.system(size: 15, weight: .bold)).foregroundColor(AppColors.darkText)
        )
        let levelTitleM = levelTitle.measure(in: size)
        context.draw(levelTitle,
                     at: CGPoint(x: 0, y: marginTop - levelTitleM.height - titleGap),
                     anchor: .topLeading)

        let tempTitle = context.resolve(
            Text("Temp(\(tUnit.unitStr))")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(trCol_Temp)
        )
        let tempTitleM = tempTitle.measure(in: size)
        context.draw(tempTitle,
                     at: CGPoint(x: totalW - tempTitleM.width,
                                 y: marginTop - tempTitleM.height - titleGap),
                     anchor: .topLeading)

        // Y-axis labels — left (Level) / right (Temperature)
        for i in 0...4 {
            let v = levelMax - levelSpan * Double(i) / 4.0
            let label = String(format: "%.2f", v)
            let resolved = context.resolve(
                Text(label).font(.system(size: 13)).foregroundColor(AppColors.darkText)
            )
            let m = resolved.measure(in: size)
            let y = marginTop + baseH * CGFloat(i) / 4
            context.draw(resolved,
                         at: CGPoint(x: marginLeft - m.width - 4, y: y - m.height / 2),
                         anchor: .topLeading)
        }
        for i in 0...4 {
            let v = tempMax - tempSpan * Double(i) / 4.0
            let label = tUnit.format(celsius: v)
            let resolved = context.resolve(
                Text(label).font(.system(size: 13)).foregroundColor(trCol_Temp)
            )
            let m = resolved.measure(in: size)
            let y = marginTop + baseH * CGFloat(i) / 4
            context.draw(resolved,
                         at: CGPoint(x: marginLeft + baseW + 4, y: y - m.height / 2),
                         anchor: .topLeading)
        }

        // Sort by time
        let sorted = records.sorted { $0.dateTime < $1.dateTime }
        let timeStart = sorted.first!.dateTime.timeIntervalSince1970
        let timeEnd = sorted.last!.dateTime.timeIntervalSince1970
        let timeSpan: Double = timeEnd > timeStart ? (timeEnd - timeStart) : 1

        // Plot points
        var lightPoints: [CGPoint] = []
        var heavyPoints: [CGPoint] = []
        var tempPoints: [CGPoint] = []
        for r in sorted {
            let t = r.dateTime.timeIntervalSince1970
            let x = marginLeft + baseW * CGFloat((t - timeStart) / timeSpan)
            let lightY = marginTop + baseH - CGFloat((r.dst * 0.01 - levelMin) / levelSpan) * baseH
            let heavyY = marginTop + baseH - CGFloat((Double(r.eeaD) * 0.01 - levelMin) / levelSpan) * baseH
            let tempY  = marginTop + baseH - CGFloat((r.temperature - tempMin) / tempSpan) * baseH
            lightPoints.append(CGPoint(x: x, y: lightY))
            heavyPoints.append(CGPoint(x: x, y: heavyY))
            tempPoints.append(CGPoint(x: x, y: tempY))
        }

        // Clip and draw the three lines
        var clipPath = Path()
        clipPath.addRect(CGRect(x: marginLeft, y: marginTop, width: baseW, height: baseH))
        context.clip(to: clipPath)

        if heavyPoints.count >= 2 {
            context.stroke(linePath(heavyPoints), with: .color(trCol_Heavy.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        if lightPoints.count >= 2 {
            context.stroke(linePath(lightPoints), with: .color(trCol_Light.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        if tempPoints.count >= 2 {
            context.stroke(linePath(tempPoints), with: .color(trCol_Temp.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        // X-axis labels + vertical dashes (timestamps)
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

                let cx = max(marginLeft, min(marginLeft + baseW - m.width, x - m.width / 2))
                context.draw(resolved,
                             at: CGPoint(x: cx, y: marginTop + baseH + 12),
                             anchor: .topLeading)
            }
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        if pts.isEmpty { return p }
        p.move(to: pts[0])
        for i in 1..<pts.count { p.addLine(to: pts[i]) }
        return p
    }
}
