// Ported from app/src/main/java/com/wws2/densitymeter/ui/component/EchoChart.kt
//
// Density-meter echo waveform chart (interpolated 816 points). Follows
// firmware VwEchoGraph_MmToPixel mapping for the X-axis, with a vertical
// blue gradient fill under the gated [Lo..Hi] segment of the wave. Vertical
// markers for D.Z. and Empty. Optional Level cursor (L) shown when the
// reading's level index lies within [deadzone..empty]. THR (Light/Heavy)
// horizontal+vertical markers are rendered when isInterface=true.
//
// The density path uses sampleUs * 1.48 / 8 mm/sample mapping over a
// 300mm display window (matches firmware MM_RANGE = 300). The interface
// path uses index-based mapping with detAreaHI as 'empty'.

import SwiftUI
import WWS2Core

private let tossBlueE        = Color(hex: 0x3182F6)
private let tossGradTopE     = Color(red: 0x31/255.0, green: 0x82/255.0, blue: 0xF6/255.0, opacity: 0xCC/255.0)
private let tossGradMidE     = Color(red: 0x31/255.0, green: 0x82/255.0, blue: 0xF6/255.0, opacity: 0x88/255.0)
private let tossGradBotE     = Color(red: 0x31/255.0, green: 0x82/255.0, blue: 0xF6/255.0, opacity: 0x22/255.0)
private let tossGridE        = Color(hex: 0xF2F4F6)
private let tossGrayE        = Color(hex: 0x8B95A1)
private let echoOrange2      = Color(hex: 0xFF8C00)

public struct EchoChart: View {
    public let echo: EchoReading?
    public var isInterface: Bool = false

    public init(echo: EchoReading?, isInterface: Bool = false) {
        self.echo = echo
        self.isInterface = isInterface
    }

    public var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 4, y: 2)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let totalPoints = EchoReading.intpSize
        let yMax: Float = 65535

        let pipeBaseMm: Int = {
            guard let r = echo else { return 0 }
            switch r.pipeDia { case 1: return 200; case 2: return 400; default: return 0 }
        }()

        // Grid (3 horizontal lines)
        for i in 1...3 {
            let y = h * CGFloat(i) / 4
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: w, y: y))
            context.stroke(p, with: .color(tossGridE), lineWidth: 1)
        }

        // X-axis labels
        if isInterface, let reading = echo {
            let emptyVal = reading.detAreaHI
            for i in 0...10 {
                let v = emptyVal - (emptyVal * i) / 10
                let dist = Double(v) * 0.01
                let label = dist >= 1.0 ? String(format: "%.1f", dist) : String(format: "%.2f", dist)
                let x = w * CGFloat(i) / 10
                drawCenteredXLabel(context: context, size: size, x: x, y: h + 8, text: label)
            }
        } else {
            for i in 0...6 {
                let mm = pipeBaseMm + (EchoReading.mmRange * i) / 6
                let x = w * CGFloat(i) / 6
                drawCenteredXLabel(context: context, size: size, x: x, y: h + 8, text: "\(mm)")
            }
        }

        // No-data fallback
        guard let reading = echo, !reading.wave.isEmpty else {
            let resolved = context.resolve(
                Text("No Data").font(.system(size: 16)).foregroundColor(tossGrayE)
            )
            let m = resolved.measure(in: size)
            context.draw(resolved,
                         at: CGPoint(x: (w - m.width) / 2, y: (h - m.height) / 2),
                         anchor: .topLeading)
            return
        }

        let wave = reading.wave

        // Density path: mm-based mapping. Interface path: index-based.
        let mmPerInterp = Float(reading.sampleUs) * 1.48 / 8
        let mmRange    = Float(EchoReading.mmRange)

        let emptyMm    = max(Float(reading.detAreaHI - pipeBaseMm), 0)
        let deadzoneMm = max(Float(reading.detAreaLO - pipeBaseMm), 0)

        let mmToIdx    = Float(totalPoints - 1) / mmRange
        let emptyIdx   = max(emptyMm * mmToIdx, 1)
        let deadzoneIdx = deadzoneMm * mmToIdx

        // Build line + fill paths within the gate
        var line = Path()
        var fill = Path()
        var started = false

        for i in 0..<wave.count {
            let x: CGFloat
            if isInterface {
                if Float(i) < deadzoneIdx || Float(i) > emptyIdx { continue }
                x = w * CGFloat(i) / CGFloat(totalPoints - 1)
            } else {
                let mm = Float(i) * mmPerInterp
                if mm < deadzoneMm || mm > emptyMm { continue }
                if mm > mmRange { break }
                x = w * CGFloat(mm) / CGFloat(mmRange)
            }
            let amp = max(min(Float(wave[i]) / yMax, 1), 0)
            let y = h - CGFloat(amp) * h
            if !started {
                line.move(to: CGPoint(x: x, y: y))
                fill.move(to: CGPoint(x: x, y: h))
                fill.addLine(to: CGPoint(x: x, y: y))
                started = true
            } else {
                line.addLine(to: CGPoint(x: x, y: y))
                fill.addLine(to: CGPoint(x: x, y: y))
            }
        }

        if started {
            let lastX: CGFloat
            if isInterface {
                let cap = min(emptyIdx, Float(totalPoints - 1))
                lastX = w * CGFloat(cap) / CGFloat(totalPoints - 1)
            } else {
                let cap = min(emptyMm, mmRange)
                lastX = w * CGFloat(cap) / CGFloat(mmRange)
            }
            fill.addLine(to: CGPoint(x: lastX, y: h))
            fill.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: tossGradTopE, location: 0.0),
                .init(color: tossGradMidE, location: 0.5),
                .init(color: tossGradBotE, location: 1.0)
            ])
            context.fill(fill, with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)
            ))
            context.stroke(line, with: .color(tossBlueE),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        // Lo / Hi vertical separators
        let dimBlue = tossBlueE.opacity(0.6)
        if isInterface {
            if deadzoneIdx > 0 {
                let dx = w * CGFloat(deadzoneIdx) / CGFloat(totalPoints - 1)
                vline(context: context, x: dx, h: h, color: dimBlue, width: 1.5)
            }
            if emptyIdx < Float(totalPoints) {
                let ex = w * CGFloat(emptyIdx) / CGFloat(totalPoints - 1)
                vline(context: context, x: ex, h: h, color: dimBlue, width: 1.5)
            }
        } else {
            if deadzoneMm > 0 {
                let dx = w * CGFloat(deadzoneMm) / CGFloat(mmRange)
                vline(context: context, x: dx, h: h, color: dimBlue, width: 1.5)
            }
            if emptyMm < mmRange {
                let ex = w * CGFloat(emptyMm) / CGFloat(mmRange)
                vline(context: context, x: ex, h: h, color: dimBlue, width: 1.5)
            }
        }

        // Level cursor (L)
        let levelIdxF = Float(reading.level)
        if isInterface {
            if levelIdxF >= deadzoneIdx && levelIdxF <= emptyIdx {
                let lx = w * CGFloat(levelIdxF) / CGFloat(totalPoints - 1)
                let i = Int(levelIdxF)
                let amp: Float = (i >= 0 && i < wave.count)
                    ? max(min(Float(wave[i]) / yMax, 1), 0) : 0
                let ly = h - CGFloat(amp) * h
                vline(context: context, x: lx, h: h, color: tossBlueE.opacity(0.2), width: 1)
                let dot = CGRect(x: lx - 6, y: ly - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(.white))
                context.stroke(Path(ellipseIn: dot), with: .color(tossBlueE), lineWidth: 2.5)
            }
        } else {
            let levelMm = levelIdxF * mmPerInterp
            if levelMm >= deadzoneMm && levelMm <= emptyMm && levelMm <= mmRange {
                let lx = w * CGFloat(levelMm) / CGFloat(mmRange)
                vline(context: context, x: lx, h: h, color: tossBlueE.opacity(0.2), width: 1)
            }
        }

        // THR (interface only)
        if isInterface {
            let dashStyle = StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            if reading.thrLightAmp > 0 {
                let y = h - CGFloat(min(max(Float(reading.thrLightAmp) / yMax, 0), 1)) * h
                hline(context: context, w: w, y: y, color: .white, style: dashStyle)
            }
            if reading.thrHeavyAmp > 0 {
                let y = h - CGFloat(min(max(Float(reading.thrHeavyAmp) / yMax, 0), 1)) * h
                hline(context: context, w: w, y: y, color: echoOrange2, style: dashStyle)
            }

            let thrEmptyMm = max(emptyMm, 1)
            let lDistX: CGFloat = reading.thrLightDist > 0
                ? w * CGFloat(max(Float(reading.thrLightDist - pipeBaseMm), 0)) / CGFloat(thrEmptyMm)
                : 0
            let hDistX: CGFloat = reading.thrHeavyDist > 0
                ? w * CGFloat(max(Float(reading.thrHeavyDist - pipeBaseMm), 0)) / CGFloat(thrEmptyMm)
                : 0
            let lhClose = abs(lDistX - hDistX) < 20

            if reading.thrLightDist > 0 && lDistX >= 0 && lDistX <= w {
                vline(context: context, x: lDistX, h: h, color: .white, width: 1.5)
            }
            if reading.thrHeavyDist > 0 && hDistX >= 0 && hDistX <= w {
                vline(context: context, x: hDistX, h: h, color: echoOrange2, width: 1.5)
            }

            if reading.thrLightDist > 0 && lDistX >= 0 && lDistX <= w {
                let resolved = context.resolve(
                    Text("L").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                )
                let m = resolved.measure(in: size)
                context.draw(resolved,
                             at: CGPoint(x: lDistX - m.width / 2, y: lhClose ? 22 : 12),
                             anchor: .topLeading)
            }
            if reading.thrHeavyDist > 0 && hDistX >= 0 && hDistX <= w {
                let resolved = context.resolve(
                    Text("H").font(.system(size: 12, weight: .bold)).foregroundColor(echoOrange2)
                )
                let m = resolved.measure(in: size)
                context.draw(resolved,
                             at: CGPoint(x: hDistX - m.width / 2, y: lhClose ? 38 : 12),
                             anchor: .topLeading)
            }
        }
    }

    // MARK: - Helpers

    private func drawCenteredXLabel(context: GraphicsContext, size: CGSize, x: CGFloat, y: CGFloat, text: String) {
        let resolved = context.resolve(
            Text(text).font(.system(size: 13)).foregroundColor(tossGrayE)
        )
        let m = resolved.measure(in: size)
        let cx = max(0, min(size.width - m.width, x - m.width / 2))
        context.draw(resolved, at: CGPoint(x: cx, y: y), anchor: .topLeading)
    }

    private func vline(context: GraphicsContext, x: CGFloat, h: CGFloat, color: Color, width: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x, y: 0))
        p.addLine(to: CGPoint(x: x, y: h))
        context.stroke(p, with: .color(color), lineWidth: width)
    }

    private func hline(context: GraphicsContext, w: CGFloat, y: CGFloat, color: Color, style: StrokeStyle) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: w, y: y))
        context.stroke(p, with: .color(color), style: style)
    }
}
