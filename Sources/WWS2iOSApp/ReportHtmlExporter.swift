// Ported from app/src/main/java/com/wws2/densitymeter/domain/ReportHtmlExporter.kt
//
// ENV130 리포트를 수정 가능한 HTML 문서로 생성한다.
// - 측정값/설정값 = HTML 표 (Word/한글에서 편집 가능)
// - 파형(실시간/평균) = Core Graphics 로 그린 PNG를 base64 로 인라인 삽입

import UIKit
import WWS2Core

enum ReportHtmlExporter {

    private static let adcMax: CGFloat = 4095

    private static func col(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    /// 인터페이스 파형을 UIImage 로 렌더 (InterfaceEchoChart 와 동일 형태).
    static func renderWaveformImage(_ reading: InterfaceEchoReading?, width: CGFloat = 900, height: CGFloat = 360) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            col(0xE0E0E0).setStroke()
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), width: 1)

            guard let r = reading, r.wave.count >= 2 else {
                let s = "No Data" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 26),
                    .foregroundColor: col(0x8B95A1),
                ]
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: (width - sz.width) / 2, y: (height - sz.height) / 2), withAttributes: attrs)
                return
            }

            let wave = r.wave
            let n = wave.count
            func xOf(_ i: CGFloat) -> CGFloat { width * i / CGFloat(n - 1) }
            func yOf(_ v: Int) -> CGFloat { height - min(max(CGFloat(v) / adcMax, 0), 1) * height }

            func drawSeg(_ start: Int, _ end: Int, _ color: UIColor) {
                let s = max(0, start)
                let e = min(n - 1, end)
                if e <= s { return }
                let line = UIBezierPath()
                let fill = UIBezierPath()
                for i in s...e {
                    let x = xOf(CGFloat(i))
                    let y = yOf(wave[i])
                    if i == s {
                        line.move(to: CGPoint(x: x, y: y))
                        fill.move(to: CGPoint(x: x, y: height))
                        fill.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        line.addLine(to: CGPoint(x: x, y: y))
                        fill.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                fill.addLine(to: CGPoint(x: xOf(CGFloat(e)), y: height))
                fill.close()
                color.setFill(); fill.fill()
                color.setStroke(); line.lineWidth = 2; line.stroke()
            }
            drawSeg(0, r.deadzone, col(0x1B4050))
            drawSeg(r.deadzone, r.empty, col(0x02F1AB))
            drawSeg(r.empty, n - 1, col(0x1B4050))

            func vline(_ x: CGFloat, _ color: UIColor) {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: height))
                color.setStroke(); p.lineWidth = 2.5; p.stroke()
            }
            if r.deadzone > 0 { vline(xOf(CGFloat(r.deadzone)), col(0x3182F6)) }
            if r.empty > 0 && r.empty < n { vline(xOf(CGFloat(r.empty)), col(0x3182F6)) }
            if r.thrLightDist > 0 { vline(xOf(CGFloat(r.thrLightDist)), col(0x666666)) }
            if r.thrHeavyDist > 0 { vline(xOf(CGFloat(r.thrHeavyDist)), col(0xFF8C00)) }

            func hdash(_ y: CGFloat, _ color: UIColor) {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: width, y: y))
                let dashes: [CGFloat] = [6, 4]
                p.setLineDash(dashes, count: dashes.count, phase: 0)
                color.setStroke(); p.lineWidth = 2.5; p.stroke()
            }
            if r.thrLightReal > 0 { hdash(yOf(r.thrLightReal), col(0x666666)) }
            if r.thrHeavyReal > 0 { hdash(yOf(r.thrHeavyReal), col(0xFF8C00)) }
        }
    }

    private static func base64Png(_ image: UIImage) -> String {
        image.pngData()?.base64EncodedString() ?? ""
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func buildHtml(_ data: ReportData) -> String {
        let realImg = base64Png(renderWaveformImage(data.realEcho))
        let avgImg = base64Png(renderWaveformImage(data.avgEcho))

        func row(_ k: String, _ v: String, _ color: String? = nil) -> String {
            let vStyle = color != nil ? " style=\"color:\(color!)\"" : ""
            return "<tr><th>\(esc(k))</th><td\(vStyle)>\(esc(v))</td></tr>"
        }
        let measurement =
            row("Light Level", String(format: "%.2f m", data.lightLevel), "#3182F6") +
            row("Heavy Level", String(format: "%.2f m", data.heavyLevel), "#FF8C00") +
            row("Temperature", String(format: "%.1f °C", data.temperatureC)) +
            row("Current", String(format: "%.2f mA", data.currentMA))
        let settings =
            row("Frequency", String(format: "%.0f kHz", data.freqMHz * 1000)) +
            row("Offset", String(format: "%.2f m", data.offset)) +
            row("Empty Distance", String(format: "%.2f m", data.emptyDistance)) +
            row("Dead Zone", String(format: "%.2f m", data.deadZone)) +
            row("Current 4mA", String(format: "%.2f m", data.set4mA)) +
            row("Current 20mA", String(format: "%.2f m", data.set20mA)) +
            row("Damping", "\(data.damping)")

        let fw = data.firmwareVersion.isEmpty ? "—" : data.firmwareVersion

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <title>\(esc(data.label)) Report</title>
        <style>
          body { font-family: 'Helvetica Neue', 'Apple SD Gothic Neo', Arial, sans-serif; color: #191F28; background: #F2F4F6; margin: 0; padding: 24px; }
          .sheet { max-width: 760px; margin: 0 auto; background: #FFFFFF; border-radius: 22px; overflow: hidden; box-shadow: 0 6px 24px rgba(0,0,0,0.08); }
          .header { background: linear-gradient(135deg, #7C3AED, #3B82F6); color: #FFFFFF; padding: 28px 28px 24px; }
          .header .name { font-size: 26px; font-weight: 800; letter-spacing: -0.5px; }
          .header .dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #4ADE80; margin-right: 8px; vertical-align: middle; }
          .header .sub { font-size: 13px; opacity: 0.9; margin-top: 10px; }
          .body { padding: 24px 28px 30px; }
          h2 { font-size: 17px; font-weight: 800; color: #191F28; letter-spacing: -0.3px; margin: 26px 0 10px; padding-left: 10px; border-left: 4px solid #3182F6; }
          h2.s { border-left-color: #7C3AED; }
          table { border-collapse: collapse; width: 100%; font-size: 14px; }
          th, td { padding: 11px 14px; text-align: left; border-bottom: 1px solid #F2F4F6; }
          th { color: #4E5968; font-weight: 600; width: 45%; background: #FAFBFC; }
          td { font-weight: 700; color: #191F28; }
          .badge { display: inline-block; font-size: 12px; font-weight: 800; padding: 4px 12px; border-radius: 999px; }
          .badge.real { color: #3182F6; background: rgba(49,130,246,0.12); }
          .badge.avg { color: #FF8C00; background: rgba(255,140,0,0.12); }
          img.wave { width: 100%; border: 1px solid #E8EBED; border-radius: 12px; margin-top: 8px; }
          @media print { body { background: #FFF; padding: 0; } .sheet { box-shadow: none; } }
        </style>
        </head>
        <body>
          <div class="sheet">
            <div class="header">
              <div class="name"><span class="dot"></span>\(esc(data.label))</div>
              <div class="sub">Interface Meter &nbsp;·&nbsp; FW \(esc(fw))<br>\(esc(data.timestamp))</div>
            </div>
            <div class="body">
              <h2>Measurement</h2>
              <table>\(measurement)</table>

              <h2 class="s">Settings</h2>
              <table>\(settings)</table>

              <h2>Waveform</h2>
              <span class="badge real">Real</span>
              <img class="wave" src="data:image/png;base64,\(realImg)" alt="Real waveform">
              <div style="height:14px"></div>
              <span class="badge avg">Average</span>
              <img class="wave" src="data:image/png;base64,\(avgImg)" alt="Average waveform">
            </div>
          </div>
        </body>
        </html>
        """
    }
}
