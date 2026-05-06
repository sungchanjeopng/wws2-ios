// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/CalibScreen.kt

import SwiftUI
import WWS2Core

private let tossBlue      = Color(hex: 0x3182F6)
private let tossDark      = Color(hex: 0x191F28)
private let tossGray      = Color(hex: 0x8B95A1)
private let tossLightGray = Color(hex: 0xB0B8C1)
private let tossDivider   = Color(hex: 0xF2F4F6)
private let tossCardBg    = Color(hex: 0xFFFFFF)
private let tossHeaderBg  = Color(hex: 0xF9FAFB)

public struct CalibScreen: View {
    @ObservedObject var vm: AppViewModel

    public var body: some View {
        let points = vm.state.calibrationPoints
        let densUnit = DensityUnit.fromInt(vm.state.densUnit)

        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("No")
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tossGray)
                        .frame(width: 0)  // weight 0.4
                    headerCol("No",            weight: 0.4, align: .center)
                    headerCol("EEA",           weight: 1.4, align: .trailing)
                    headerCol("LV(\(densUnit.unitStr))", weight: 1.4, align: .trailing)
                    headerCol("Date",          weight: 2.5, align: .center)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(tossHeaderBg)
                .clipShape(RoundedCornerOnly(radius: 20, corners: [.topLeft, .topRight]))

                Rectangle().fill(tossDivider).frame(height: 1)

                if points.isEmpty {
                    Text("No calibration data")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tossLightGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                        let active = pt.fEEA || pt.fLV
                        HStack(spacing: 0) {
                            cellCol("\(i + 1)", weight: 0.4, align: .center,
                                    color: active ? tossBlue : tossLightGray, weight700: true)
                            cellCol(pt.fEEA ? "\(pt.eea)" : "--", weight: 1.4, align: .trailing,
                                    color: pt.fEEA ? tossDark : tossLightGray, weight700: false)
                            cellCol(pt.fLV ? densUnit.format(raw: pt.density) : "--",
                                    weight: 1.4, align: .trailing,
                                    color: pt.fLV ? tossDark : tossLightGray, weight700: false)
                            cellCol(active
                                    ? String(format: "%02d.%02d.%02d %02d:%02d",
                                             pt.year % 100, pt.month, pt.day, pt.hour, pt.minute)
                                    : "--",
                                    weight: 2.5, align: .center, fontSize: 14,
                                    color: active ? tossGray : tossLightGray, weight700: false)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        if i < points.count - 1 {
                            Rectangle()
                                .fill(tossDivider)
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(tossCardBg)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: AppColors.cardShadow, radius: 6, y: 2)
            .padding(12)
        }
    }

    private func headerCol(_ text: String, weight: CGFloat, align: TextAlignment) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tossGray)
            .multilineTextAlignment(align)
            .frame(maxWidth: .infinity, alignment: align == .center ? .center : align == .trailing ? .trailing : .leading)
            .layoutPriority(weight)
    }

    private func cellCol(_ text: String, weight: CGFloat, align: TextAlignment,
                         fontSize: CGFloat = 15, color: Color, weight700: Bool) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight700 ? .bold : .semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(align)
            .frame(maxWidth: .infinity, alignment: align == .center ? .center : align == .trailing ? .trailing : .leading)
            .layoutPriority(weight)
    }
}

/// Helper shape: rounds only the corners specified.
private struct RoundedCornerOnly: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                             cornerRadii: CGSize(width: radius, height: radius))
        return Path(p.cgPath)
    }
}
