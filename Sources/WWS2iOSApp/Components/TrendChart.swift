// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/TrendChart.kt
//
// Density-meter trend chart with Android-like interaction:
// - axis-specific pinch zoom in/out (horizontal fingers -> X only, vertical fingers -> Y only)
// - one-finger pan after zoom
// - long press / hold crosshair tooltip
// - double tap reset

import SwiftUI
import WWS2Core

public struct TrendChart: View {
    public let records: [TrendRecord]
    public let densUnit: Int
    public let tempUnit: Int

    @State private var scaleX: CGFloat = 1
    @State private var scaleY: CGFloat = 1
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var touchPos: CGPoint? = nil

    public init(records: [TrendRecord], densUnit: Int = 0, tempUnit: Int = 0) {
        self.records = records
        self.densUnit = densUnit
        self.tempUnit = tempUnit
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    draw(context: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(chartDragGesture(size: geo.size))
                .simultaneousGesture(TapGesture(count: 2).onEnded { resetZoom() })
                .overlay {
                    AxisPinchOverlay { xDelta, yDelta, center in
                        zoom(xDelta: xDelta, yDelta: yDelta, center: center, size: geo.size)
                        touchPos = nil
                    } onEnded: {
                        touchPos = nil
                    }
                }

                if scaleX > 1.01 || scaleY > 1.01 {
                    Button(action: resetZoom) {
                        Text(String(format: "%.1fx Reset", Double(max(scaleX, scaleY))))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppColors.white.opacity(0.88))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
        .onChange(of: records.count) { _ in
            if scaleX == 1 && scaleY == 1 { offsetX = 0; offsetY = 0 }
            touchPos = nil
        }
    }

    private func chartDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let margins = chartMargins(totalH: size.height)
                let baseW = max(1, size.width - margins.left - margins.right)
                let baseH = max(1, size.height - margins.top - margins.bottom)
                if scaleX > 1.01 || scaleY > 1.01 {
                    offsetX = clampOffset(offsetX + value.translation.width * 0.18, base: baseW, scale: scaleX)
                    offsetY = clampOffset(offsetY + value.translation.height * 0.18, base: baseH, scale: scaleY)
                    touchPos = nil
                } else {
                    touchPos = value.location
                }
            }
            .onEnded { _ in touchPos = nil }
    }

    private func zoom(xDelta: CGFloat, yDelta: CGFloat, center: CGPoint, size: CGSize) {
        let margins = chartMargins(totalH: size.height)
        let baseW = max(1, size.width - margins.left - margins.right)
        let baseH = max(1, size.height - margins.top - margins.bottom)
        let oldSx = scaleX
        let oldSy = scaleY
        scaleX = min(max(scaleX * xDelta, 1), 10)
        scaleY = min(max(scaleY * yDelta, 1), 10)
        let cx = center.x - margins.left
        let cy = center.y - margins.top
        if oldSx > 0 { offsetX = cx - (cx - offsetX) * scaleX / oldSx }
        if oldSy > 0 { offsetY = cy - (cy - offsetY) * scaleY / oldSy }
        offsetX = clampOffset(offsetX, base: baseW, scale: scaleX)
        offsetY = clampOffset(offsetY, base: baseH, scale: scaleY)
    }

    private func resetZoom() {
        scaleX = 1; scaleY = 1; offsetX = 0; offsetY = 0; touchPos = nil
    }

    private func clampOffset(_ value: CGFloat, base: CGFloat, scale: CGFloat) -> CGFloat {
        min(0, max(-(base * (scale - 1)), value))
    }

    private func chartMargins(totalH: CGFloat) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        (42, 42, max(38, min(58, totalH * 0.08)), max(42, min(58, totalH * 0.09)))
    }

    private func draw(context ctx: GraphicsContext, size: CGSize) {
        var context = ctx
        let totalW = size.width
        let totalH = size.height
        let dUnit = DensityUnit.fromInt(densUnit)
        let tUnit = TemperatureUnit.fromInt(tempUnit)
        let m = chartMargins(totalH: totalH)
        let marginLeft = m.left, marginRight = m.right, marginTop = m.top, marginBottom = m.bottom
        let baseW = totalW - marginLeft - marginRight
        let baseH = totalH - marginTop - marginBottom
        if baseW <= 0 || baseH <= 0 { return }

        if records.isEmpty {
            let resolved = context.resolve(Text("No Data").font(.system(size: 16)).foregroundColor(AppColors.grayLabel))
            let ms = resolved.measure(in: size)
            context.draw(resolved, at: CGPoint(x: (totalW - ms.width) / 2, y: (totalH - ms.height) / 2), anchor: .topLeading)
            return
        }

        var dstMax = records.first!.dst
        var tempMin = records.first!.temperature
        var tempMax = records.first!.temperature
        for r in records {
            dstMax = max(dstMax, r.dst)
            tempMin = min(tempMin, r.temperature)
            tempMax = max(tempMax, r.temperature)
        }
        let dstMin = 0.0
        dstMax = dstMax < 1.0 ? 1.0 : dstMax * 1.2
        tempMin -= 5; tempMax += 5
        let dstSpan = abs(dstMax - dstMin) < 0.001 ? 1.0 : (dstMax - dstMin)
        let tempSpan = abs(tempMax - tempMin) < 0.001 ? 1.0 : (tempMax - tempMin)
        let sorted = records.sorted { $0.dateTime < $1.dateTime }
        let timeStart = sorted.first!.dateTime.timeIntervalSince1970
        let timeEnd = sorted.last!.dateTime.timeIntervalSince1970
        let timeSpan = timeEnd > timeStart ? (timeEnd - timeStart) : 1

        let chartW = baseW * scaleX
        let chartH = baseH * scaleY
        let ox = clampOffset(offsetX, base: baseW, scale: scaleX)
        let oy = clampOffset(offsetY, base: baseH, scale: scaleY)

        let visDstMax = dstMin + dstSpan * Double(oy + chartH) / Double(chartH)
        let visDstMin = dstMin + dstSpan * Double(oy + chartH - baseH) / Double(chartH)
        let visTempMax = tempMin + tempSpan * Double(oy + chartH) / Double(chartH)
        let visTempMin = tempMin + tempSpan * Double(oy + chartH - baseH) / Double(chartH)
        let visDstSpan = visDstMax - visDstMin
        let visTempSpan = visTempMax - visTempMin
        let visTimeStart = timeStart + timeSpan * Double(-ox / chartW)
        let visTimeEnd = timeStart + timeSpan * Double((baseW - ox) / chartW)

        drawText(context: context, size: size, text: "Density(\(dUnit.unitStr))", size: 15, weight: .bold, color: AppColors.primary, origin: CGPoint(x: 0, y: marginTop - 48))
        let tempTitleText = "Temp(\(tUnit.unitStr))"
        let tempTitle = context.resolve(Text(tempTitleText).font(.system(size: 15, weight: .bold)).foregroundColor(AppColors.temperature))
        let tempTitleM = tempTitle.measure(in: size)
        context.draw(tempTitle, at: CGPoint(x: totalW - tempTitleM.width, y: marginTop - 30 - tempTitleM.height), anchor: .topLeading)

        let dashStyle = StrokeStyle(lineWidth: 1, dash: [8, 6])
        for i in 0...4 {
            let y = marginTop + baseH * CGFloat(i) / 4
            var p = Path(); p.move(to: CGPoint(x: marginLeft, y: y)); p.addLine(to: CGPoint(x: marginLeft + baseW, y: y))
            context.stroke(p, with: .color(Color(hex: 0xCCCCCC)), style: dashStyle)
            let dVal = visDstMax - visDstSpan * Double(i) / 4
            let dLabel = context.resolve(Text(dUnit.format(raw: dVal)).font(.system(size: 12)).foregroundColor(AppColors.primary))
            let dm = dLabel.measure(in: size)
            context.draw(dLabel, at: CGPoint(x: marginLeft - dm.width - 4, y: y - dm.height / 2), anchor: .topLeading)
            let tVal = visTempMax - visTempSpan * Double(i) / 4
            let tLabel = context.resolve(Text(tUnit.format(celsius: tVal)).font(.system(size: 12)).foregroundColor(AppColors.temperature))
            let tm = tLabel.measure(in: size)
            context.draw(tLabel, at: CGPoint(x: marginLeft + baseW + 4, y: y - tm.height / 2), anchor: .topLeading)
        }

        drawTimeAxis(context: context, size: size, marginLeft: marginLeft, marginTop: marginTop, baseW: baseW, baseH: baseH, marginBottom: marginBottom, start: visTimeStart, end: visTimeEnd, dashStyle: dashStyle)

        var densityPoints: [CGPoint] = []
        var tempPoints: [CGPoint] = []
        for r in sorted {
            let t = r.dateTime.timeIntervalSince1970
            let x = marginLeft + ox + chartW * CGFloat((t - timeStart) / timeSpan)
            let dy = marginTop + oy + chartH - CGFloat((r.dst - dstMin) / dstSpan) * chartH
            let ty = marginTop + oy + chartH - CGFloat((r.temperature - tempMin) / tempSpan) * chartH
            densityPoints.append(CGPoint(x: x, y: dy))
            tempPoints.append(CGPoint(x: x, y: ty))
        }

        var clipPath = Path(); clipPath.addRect(CGRect(x: marginLeft, y: marginTop, width: baseW, height: baseH))
        context.clip(to: clipPath)
        if densityPoints.count >= 2 { context.stroke(smoothPath(densityPoints), with: .color(AppColors.primary), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)) }
        if tempPoints.count >= 2 { context.stroke(smoothPath(tempPoints), with: .color(AppColors.temperature.opacity(0.4)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)) }
        if let touchPos { drawCrosshair(context: context, size: size, touch: touchPos, sorted: sorted, densityPoints: densityPoints, tempPoints: tempPoints, dUnit: dUnit, tUnit: tUnit, chartRect: CGRect(x: marginLeft, y: marginTop, width: baseW, height: baseH)) }
    }

    private func drawTimeAxis(context: GraphicsContext, size: CGSize, marginLeft: CGFloat, marginTop: CGFloat, baseW: CGFloat, baseH: CGFloat, marginBottom: CGFloat, start: TimeInterval, end: TimeInterval, dashStyle: StrokeStyle) {
        var context = context
        let labelCount = 5
        let utcCal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC") ?? .current; return c }()
        for i in 0..<labelCount {
            let t = start + (end - start) * Double(i) / Double(labelCount - 1)
            let comps = utcCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: t))
            let text = String(format: "%02d:%02d:%02d\n%02d/%02d/%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0, (comps.year ?? 0) % 100, comps.month ?? 0, comps.day ?? 0)
            let resolved = context.resolve(Text(text).font(.system(size: 9)).foregroundColor(AppColors.grayLabel))
            let ms = resolved.measure(in: size)
            let rawX = marginLeft + baseW * CGFloat(i) / CGFloat(labelCount - 1)
            let x = i == 0 ? rawX + 12 : (i == labelCount - 1 ? rawX - 12 : rawX)
            var p = Path(); p.move(to: CGPoint(x: x, y: marginTop)); p.addLine(to: CGPoint(x: x, y: marginTop + baseH))
            context.stroke(p, with: .color(Color(hex: 0xCCCCCC)), style: dashStyle)
            let cx = max(marginLeft, min(marginLeft + baseW - ms.width, x - ms.width / 2))
            context.draw(resolved, at: CGPoint(x: cx, y: marginTop + baseH + marginBottom * 0.35), anchor: .topLeading)
        }
    }

    private func drawCrosshair(context: GraphicsContext, size: CGSize, touch: CGPoint, sorted: [TrendRecord], densityPoints: [CGPoint], tempPoints: [CGPoint], dUnit: DensityUnit, tUnit: TemperatureUnit, chartRect: CGRect) {
        guard chartRect.contains(touch), !densityPoints.isEmpty else { return }
        var context = context
        let idx = densityPoints.indices.min { abs(densityPoints[$0].x - touch.x) < abs(densityPoints[$1].x - touch.x) } ?? 0
        let x = densityPoints[idx].x
        var v = Path(); v.move(to: CGPoint(x: x, y: chartRect.minY)); v.addLine(to: CGPoint(x: x, y: chartRect.maxY))
        context.stroke(v, with: .color(AppColors.darkText.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        let r = sorted[idx]
        let text = "D \(dUnit.format(raw: r.dst))\nT \(tUnit.format(celsius: r.temperature))"
        let label = context.resolve(Text(text).font(.system(size: 11, weight: .bold)).foregroundColor(AppColors.darkText))
        let ms = label.measure(in: size)
        let lx = min(max(chartRect.minX + 4, x + 8), chartRect.maxX - ms.width - 8)
        let ly = chartRect.minY + 8
        var bg = Path(roundedRect: CGRect(x: lx - 5, y: ly - 4, width: ms.width + 10, height: ms.height + 8), cornerRadius: 8)
        context.fill(bg, with: .color(AppColors.white.opacity(0.9)))
        context.draw(label, at: CGPoint(x: lx, y: ly), anchor: .topLeading)
    }

    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var p = Path(); if pts.isEmpty { return p }; p.move(to: pts[0])
        for i in 1..<pts.count {
            let prev = pts[i - 1], cur = pts[i], cx = (prev.x + cur.x) / 2
            p.addCurve(to: cur, control1: CGPoint(x: cx, y: prev.y), control2: CGPoint(x: cx, y: cur.y))
        }
        return p
    }

    private func drawText(context: GraphicsContext, size: CGSize, text: String, size pt: CGFloat, weight: Font.Weight, color: Color, origin: CGPoint) {
        let resolved = context.resolve(Text(text).font(.system(size: pt, weight: weight)).foregroundColor(color))
        context.draw(resolved, at: origin, anchor: .topLeading)
    }
}
