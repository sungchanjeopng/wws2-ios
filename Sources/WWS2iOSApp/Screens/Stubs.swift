// Screen scaffolds. Each view ports the navigation/skeleton of its Compose
// counterpart from `app/src/main/java/com/wws2/densitymeter/ui/screen/`,
// with content marked as TODO until the full UI is filled in. The shell
// boots with these stubs so layout, navigation, theming, and state plumbing
// can all be exercised end-to-end on a simulator before each screen's body
// is fleshed out one by one.

import SwiftUI
import WWS2Core

// MARK: - Helper: section card used by stubs

struct StubCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.darkText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppColors.cardShadow, radius: 6, y: 2)
        .padding(.horizontal, 16)
    }
}

// MARK: - Top-level tab stubs

// MainTabScreen ported in Screens/MainTabScreen.swift.

// EchoTabScreen ported in Screens/EchoTabScreen.swift.

// TrendTabScreen ported in Screens/TrendTabScreen.swift.

// DiagnosticsTabScreen ported in Screens/DiagnosticsTabScreen.swift.
// MenuTabScreen ported in Screens/MenuTabScreen.swift.

// MARK: - Sub-page stubs (Pairing, Calib, Upload, Download, Chatbot, Pin, BleError)

// PairingScreen ported in Screens/PairingScreen.swift.

// CalibScreen ported in Screens/CalibScreen.swift.

// UploadScreen ported in Screens/UploadScreen.swift.

// DataDownloadScreen ported in Screens/DataDownloadScreen.swift.

public struct ChatbotScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            StubCard(title: "AI Chatbot") {
                Text("// TODO: port ChatbotScreen.kt (962 lines)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
            }
        }
    }
}

// PinScreen ported in Screens/PinScreen.swift.
