// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/InterfaceEchoChart.kt
//
// Compose Canvas → SwiftUI Canvas. Drawing is line-by-line equivalent:
// fills the wave under three segments (DZ-left / DZ→Empty / Empty-right),
// vertical DZ/Empty separators, horizontal Light/Heavy THR dashed lines,
// vertical Light/Heavy distance markers, and a 10-step X-axis label strip
// drawn in EMPTY-meters (label direction is intentionally inverted relative
// to the wave — matches firmware UX).

import SwiftUI
import WWS2Core

private let echoColMain     = Color(hex: 0x02F1AB)   // DZ→Empty wave
private let echoColOut      = Color(hex: 0x1B4050)   // outer wave (DZ left / Empty right)
private let echoColThrLight = Color(hex: 0x666666)
private let echoColThrHeavy = Color(hex: 0xFF8C00)
private let echoColDzEmpty  = Color(hex: 0x3182F6)
private let echoColLabel    = Color(hex: 0x8B95A1)

private let echoAdcMax: Float = 4095

public struct InterfaceEchoChart: View {
    public let echo: InterfaceEchoReading?
    public init(echo: InterfaceEchoReading?) { self.echo = echo }

    public var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let w = size.width
        // SwiftUI Canvas clips to its own bounds, so the x-axis label strip
        // must live INSIDE the canvas — reserve the bottom for it. (Android's
        // Compose Canvas doesn't clip, which is why the same h+4 drawText
        // worked there but silently disappeared here.)
        let axisPad: CGFloat = 18
        let h = size.height - axisPad

        guard let reading = echo, !reading.wave.isEmpty else {
            let label = Text("No Data").font(.system(size: 16)).foregroundColor(echoColLabel)
            let resolved = context.resolve(label)
            let measured = resolved.measure(in: size)
            context.draw(resolved,
                         at: CGPoint(x: (w - measured.width) / 2,
                                     y: (h - measured.height) / 2),
                         anchor: .topLeading)
            return
        }

        let wave = reading.wave
        let n = wave.count
        if n < 2 { return }
        let deadzone = max(0, min(reading.deadzone, n - 1))
        let empty    = max(0, min(reading.empty,    n - 1))

        // Y축 라벨용 왼쪽 여백 (X축 하단 여백과 동일한 방식)
        let yTickProbe = context.resolve(
            Text("3.0").font(.system(size: 10, weight: .medium)).foregroundColor(echoColLabel)
        )
        let leftPad = yTickProbe.measure(in: size).width + 8
        let plotW = w - leftPad

        func xOf(_ idx: Int)   -> CGFloat { leftPad + CGFloat(idx) * plotW / CGFloat(n - 1) }
        func xOfF(_ idx: CGFloat) -> CGFloat { leftPad + idx * plotW / CGFloat(n - 1) }
        func yOf(_ v: Int) -> CGFloat {
            let clamped = min(max(Float(v) / echoAdcMax, 0), 1)
            return h - CGFloat(clamped) * h
        }

        func drawSegment(_ start: Int, _ end: Int, _ color: Color) {
            let s = max(start, 0)
            let e = min(end, n - 1)
            guard s < e else { return }
            var line = Path()
            var fill = Path()
            var started = false
            var lastX: CGFloat = 0
            for i in s...e {
                let x = xOf(i)
                let y = yOf(wave[i])
                if !started {
                    line.move(to: CGPoint(x: x, y: y))
                    fill.move(to: CGPoint(x: x, y: h))
                    fill.addLine(to: CGPoint(x: x, y: y))
                    started = true
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                    fill.addLine(to: CGPoint(x: x, y: y))
                }
                lastX = x
            }
            guard started else { return }
            fill.addLine(to: CGPoint(x: lastX, y: h))
            fill.closeSubpath()
            context.fill(fill, with: .color(color))
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        drawSegment(0,        deadzone, echoColOut)
        drawSegment(deadzone, empty,    echoColMain)
        drawSegment(empty,    n - 1,    echoColOut)

        // Vertical DZ / Empty markers
        if deadzone > 0 {
            let x = xOf(deadzone)
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            context.stroke(p, with: .color(echoColDzEmpty), lineWidth: 2.5)
        }
        if empty > 0 && empty < n {
            let x = xOf(empty)
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            context.stroke(p, with: .color(echoColDzEmpty), lineWidth: 2.5)
        }

        // Horizontal THR dashed lines
        let dashStyle = StrokeStyle(lineWidth: 2.5, dash: [6, 4])
        if reading.thrLightReal > 0 {
            let y = yOf(reading.thrLightReal)
            var p = Path(); p.move(to: CGPoint(x: leftPad, y: y)); p.addLine(to: CGPoint(x: w, y: y))
            context.stroke(p, with: .color(echoColThrLight), style: dashStyle)
        }
        if reading.thrHeavyReal > 0 {
            let y = yOf(reading.thrHeavyReal)
            var p = Path(); p.move(to: CGPoint(x: leftPad, y: y)); p.addLine(to: CGPoint(x: w, y: y))
            context.stroke(p, with: .color(echoColThrHeavy), style: dashStyle)
        }

        // Vertical L / H markers
        if reading.thrLightDist > 0 {
            let x = xOfF(CGFloat(reading.thrLightDist))
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            context.stroke(p, with: .color(echoColThrLight), lineWidth: 2.5)
        }
        if reading.thrHeavyDist > 0 {
            let x = xOfF(CGFloat(reading.thrHeavyDist))
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            context.stroke(p, with: .color(echoColThrHeavy), lineWidth: 2.5)
        }

        // Y-axis ticks: 1.0 / 2.0 / 3.0 + unit "V" at the top (ADC 0~4095 = 0~3.3V)
        let vUnit = context.resolve(
            Text("V").font(.system(size: 10, weight: .medium)).foregroundColor(echoColLabel)
        )
        let vSize = vUnit.measure(in: size)
        context.draw(vUnit, at: CGPoint(x: leftPad - vSize.width - 6, y: 0), anchor: .topLeading)
        for volt in [1, 2, 3] {
            let raw = Int(Float(volt) / 3.3 * echoAdcMax)
            let y = yOf(raw)
            var guide = Path()
            guide.move(to: CGPoint(x: leftPad, y: y))
            guide.addLine(to: CGPoint(x: w, y: y))
            context.stroke(guide, with: .color(echoColLabel.opacity(0.25)), lineWidth: 1)
            let resolved = context.resolve(
                Text("\(volt).0").font(.system(size: 10, weight: .medium)).foregroundColor(echoColLabel)
            )
            let measured = resolved.measure(in: size)
            let top = min(max(0, y - measured.height / 2), h - measured.height)
            context.draw(resolved, at: CGPoint(x: leftPad - measured.width - 6, y: top), anchor: .topLeading)
        }

        // 10-step X-axis label strip (EMPTY-meters, intentionally inverted vs wave)
        let emptyM = Float(empty) * 0.01
        let totalRangeM = Float(n - 1) * 0.01
        if emptyM > 0 && totalRangeM > 0 {
            let mUnit = context.resolve(
                Text("m").font(.system(size: 11, weight: .medium)).foregroundColor(echoColLabel)
            )
            let mSize = mUnit.measure(in: size)
            context.draw(mUnit, at: CGPoint(x: w - mSize.width, y: h + 4), anchor: .topLeading)
            for i in 0...10 {
                let v = emptyM - (emptyM / 10.0) * Float(i)
                let x = leftPad + plotW * CGFloat((emptyM - v) / totalRangeM)
                if x < leftPad || x > w { continue }
                let label = String(format: "%.2f", v)
                let resolved = context.resolve(
                    Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(echoColLabel)
                )
                let measured = resolved.measure(in: size)
                let centeredX = max(0, min(w - mSize.width - 6 - measured.width, x - measured.width / 2))
                context.draw(resolved, at: CGPoint(x: centeredX, y: h + 4), anchor: .topLeading)
            }
        }
    }
}
