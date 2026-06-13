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
    static func renderWaveformImage(_ reading: InterfaceEchoReading?, width: CGFloat = 900, totalHeight: CGFloat = 400) -> UIImage {
        let axisPad: CGFloat = 34
        let height = totalHeight - axisPad
        let yAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: col(0x8B95A1),
        ]
        // Y축 라벨용 왼쪽 여백 (X축 하단 여백과 동일한 방식)
        let leftPad = ("3.0" as NSString).size(withAttributes: yAttrs).width + 12
        let plotW = width - leftPad
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
            col(0xE0E0E0).setStroke()
            cg.stroke(CGRect(x: leftPad, y: 0.5, width: width - leftPad - 0.5, height: height - 1), width: 1)

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
            func xOf(_ i: CGFloat) -> CGFloat { leftPad + plotW * i / CGFloat(n - 1) }
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
                p.move(to: CGPoint(x: leftPad, y: y))
                p.addLine(to: CGPoint(x: width, y: y))
                let dashes: [CGFloat] = [6, 4]
                p.setLineDash(dashes, count: dashes.count, phase: 0)
                color.setStroke(); p.lineWidth = 2.5; p.stroke()
            }
            if r.thrLightReal > 0 { hdash(yOf(r.thrLightReal), col(0x666666)) }
            if r.thrHeavyReal > 0 { hdash(yOf(r.thrHeavyReal), col(0xFF8C00)) }

            // Y-axis ticks: 1.0 / 2.0 / 3.0 + unit "V" at the top (ADC 0~4095 = 0~3.3V)
            let vLabel = "V" as NSString
            let vSize = vLabel.size(withAttributes: yAttrs)
            vLabel.draw(at: CGPoint(x: leftPad - vSize.width - 6, y: 2), withAttributes: yAttrs)
            for volt in [1, 2, 3] {
                let raw = Int(CGFloat(volt) / 3.3 * adcMax)
                let y = yOf(raw)
                let guide = UIBezierPath()
                guide.move(to: CGPoint(x: leftPad, y: y))
                guide.addLine(to: CGPoint(x: width, y: y))
                col(0x8B95A1).withAlphaComponent(0.25).setStroke()
                guide.lineWidth = 1
                guide.stroke()
                let yLabel = "\(volt).0" as NSString
                let labelSize = yLabel.size(withAttributes: yAttrs)
                let ly = min(max(vSize.height + 4, y - labelSize.height / 2), height - labelSize.height)
                yLabel.draw(at: CGPoint(x: leftPad - labelSize.width - 6, y: ly), withAttributes: yAttrs)
            }

            // X-axis labels (same layout as InterfaceEchoChart): 10 ticks
            // from Empty (left) to 0.00m (right).
            let emptyM = CGFloat(r.empty) * 0.01
            let totalRangeM = CGFloat(n - 1) * 0.01
            if emptyM > 0 && totalRangeM > 0 {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: col(0x8B95A1),
                ]
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                var attrsCentered = attrs
                attrsCentered[.paragraphStyle] = para
                let mLabel = "m" as NSString
                let mSize = mLabel.size(withAttributes: attrs)
                mLabel.draw(at: CGPoint(x: width - mSize.width - 2, y: height + 6), withAttributes: attrs)
                for i in 0...10 {
                    let v = emptyM - (emptyM / 10.0) * CGFloat(i)
                    let x = leftPad + plotW * (emptyM - v) / totalRangeM
                    if x < leftPad || x > width { continue }
                    let label = String(format: "%.2f", Double(v)) as NSString
                    let sz = label.size(withAttributes: attrs)
                    let cx = min(max(x, leftPad), width - mSize.width - 10 - sz.width / 2)
                    label.draw(at: CGPoint(x: cx - sz.width / 2, y: height + 6), withAttributes: attrs)
                }
            }
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

    /// 파형 2장(Real/Avg)의 base64 PNG. Word(MHTML) export에서 별도 파트로 분리할 때 사용.
    static func waveImagesBase64(_ data: ReportData) -> (String, String) {
        (base64Png(renderWaveformImage(data.realEcho)),
         base64Png(renderWaveformImage(data.avgEcho)))
    }

    static func buildHtml(_ data: ReportData) -> String {
        let (realB64, avgB64) = waveImagesBase64(data)
        return buildHtml(data,
                         realSrc: "data:image/png;base64,\(realB64)",
                         avgSrc: "data:image/png;base64,\(avgB64)")
    }

    /// forWord: Word(MHTML)용 변형 — Word가 div CSS background/gradient와 CSS img
    /// width를 무시하므로 헤더는 table+bgcolor, 이미지는 width 속성, 코멘트는 table로.
    static func buildHtml(_ data: ReportData, realSrc: String, avgSrc: String, forWord: Bool = false) -> String {

        func row(_ k: String, _ v: String, _ color: String? = nil) -> String {
            let vStyle = color != nil ? " style=\"color:\(color!)\"" : ""
            return "<tr><th>\(esc(k))</th><td\(vStyle)>\(esc(v))</td></tr>"
        }
        let measurement =
            row("Light Level", String(format: "%.2f m", data.lightLevel), "#3182F6") +
            row("Heavy Level", String(format: "%.2f m", data.heavyLevel), "#FF8C00") +
            row("Temperature", String(format: "%.1f °C", data.temperatureC)) +
            row("Current", String(format: "%.2f mA", data.currentMA))
        let thrLightStr = data.thrLightMode == 1
            ? String(format: "%.1f V", Double(data.thrLightSet) / 10.0)
            : "\(data.thrLightSet) %"
        let thrHeavyStr = data.thrHeavyMode == 1
            ? String(format: "%.1f V", Double(data.thrHeavySet) / 10.0)
            : "\(data.thrHeavySet) %"
        func row4(_ k1: String, _ v1: String, _ k2: String?, _ v2: String?) -> String {
            let cell2 = (k2 != nil && v2 != nil)
                ? "<th>\(esc(k2!))</th><td>\(esc(v2!))</td>"
                : "<th></th><td></td>"
            return "<tr><th>\(esc(k1))</th><td>\(esc(v1))</td>\(cell2)</tr>"
        }
        let settings =
            row4("Echo Amp", "\(data.echoAmp)",
                 "Frequency", String(format: "%.0f kHz", data.freqMHz * 1000)) +
            row4("Thr.Light", thrLightStr,
                 "Thr.Heavy", thrHeavyStr) +
            row4("Offset", String(format: "%.2f m", data.offset),
                 "Empty", String(format: "%.2f m", data.emptyDistance)) +
            row4("Dead Zone", String(format: "%.2f m", data.deadZone),
                 "Damping", "\(data.damping)") +
            row4("Set 4mA", String(format: "%.2f m", data.set4mA),
                 "Set 20mA", String(format: "%.2f m", data.set20mA))

        let headerTitle = esc((data.title?.isEmpty == false) ? data.title! : data.label)
        // Word는 div CSS background(gradient 포함)를 무시 → table+bgcolor로 대체
        let header = forWord ? """
        <table width="100%" cellpadding="0" cellspacing="0" style="border:none; border-collapse:collapse;"><tr>
          <td bgcolor="#7C3AED" style="background:#7C3AED; padding:24px 28px; border:none;">
            <span style="font-size:26px; font-weight:800; color:#FFFFFF;"><span style="color:#4ADE80;">&#9679;</span>&nbsp;\(headerTitle)</span><br>
            <span style="font-size:13px; color:#EDE9FE;">ENV130</span><br>
            <span style="font-size:13px; color:#EDE9FE;">\(esc(data.timestamp))</span>
          </td>
        </tr></table>
        """ : """
        <div class="header">
          <div class="name"><span class="dot"></span>\(headerTitle)</div>
          <div class="sub">ENV130<br>\(esc(data.timestamp))</div>
        </div>
        """
        // Word는 CSS width:100%를 무시하고 원본 px로 그림 → A4 안에 들어오게 width 속성 지정
        let imgAttr = forWord ? " width=\"620\"" : ""
        let commentBox = forWord
            ? "<table width=\"100%\" style=\"border-collapse:collapse;\"><tr><td style=\"border:1.5px solid #C9CFD6; padding:14px; font-size:14px; height:60px; vertical-align:top;\">\(esc(data.comment ?? ""))</td></tr></table>"
            : "<div class=\"comment\">\(esc(data.comment ?? ""))</div>"

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
          table { border-collapse: collapse; width: 100%; font-size: 14px; border: 1.5px solid #C9CFD6; }
          th, td { padding: 11px 14px; text-align: left; border: 1px solid #D8DDE3; }
          th { color: #4E5968; font-weight: 600; background: #FAFBFC; }
          td { font-weight: 700; color: #191F28; }
          table.kv2 th { width: 45%; }
          table.kv4 th { width: 22%; }
          table.kv4 td { width: 28%; }
          tr.gh td { font-size: 11px; font-weight: 800; color: #8B95A1; letter-spacing: 0.8px; background: #FFFFFF; border-bottom: none; padding: 14px 14px 4px; text-transform: uppercase; }
          .badge { display: inline-block; font-size: 12px; font-weight: 800; padding: 4px 12px; border-radius: 999px; }
          .badge.real { color: #3182F6; background: rgba(49,130,246,0.12); }
          .badge.avg { color: #FF8C00; background: rgba(255,140,0,0.12); }
          img.wave { width: 100%; border: 1px solid #E8EBED; border-radius: 12px; margin-top: 8px; }
          .comment { border: 1.5px solid #C9CFD6; min-height: 90px; padding: 14px; font-size: 14px; font-weight: 600; color: #191F28; white-space: pre-wrap; }
          @media print { body { background: #FFF; padding: 0; } .sheet { box-shadow: none; } }
        </style>
        </head>
        <body>
          <div class="sheet">
            \(header)
            <div class="body">
              <h2>Measurement</h2>
              <table class="kv2">\(measurement)</table>

              <h2>Parameter</h2>
              <table class="kv4">\(settings)</table>

              <h2>Echo</h2>
              <span class="badge real">Real</span>
              <img class="wave"\(imgAttr) src="\(realSrc)" alt="Real waveform">
              <div style="height:14px"></div>
              <span class="badge avg">Average</span>
              <img class="wave"\(imgAttr) src="\(avgSrc)" alt="Average waveform">

              <h2>Comment</h2>
              \(commentBox)
            </div>
          </div>
        </body>
        </html>
        """
    }
}
