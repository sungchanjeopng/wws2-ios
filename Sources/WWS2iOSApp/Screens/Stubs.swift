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

public struct MainTabScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StubCard(title: "Main Tab") {
                    Text("Active device: \(vm.state.activeDeviceLabel.isEmpty ? "—" : vm.state.activeDeviceLabel)")
                    Text("Connected devices: \(vm.state.connectedDevices.count)")
                    Text("// TODO: port app/src/main/java/com/wws2/densitymeter/ui/screen/MainTabScreen.kt (265 lines)")
                        .font(.caption)
                        .foregroundStyle(AppColors.grayLabel)
                }
            }
            .padding(.vertical, 16)
        }
    }
}

public struct EchoTabScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            StubCard(title: "Echo Tab") {
                Text("Echo level: \(vm.state.echoReading.map { String(format: "%.2f", $0.level) } ?? "—")")
                Text("// TODO: port EchoTabScreen.kt (232 lines) + EchoChart.kt (324)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
            }
        }
    }
}

public struct TrendTabScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            StubCard(title: "Trend Tab") {
                Text("Records: \(vm.state.trendRecords.count)")
                Text("// TODO: port TrendTabScreen.kt (199 lines) + TrendChart.kt (374)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
            }
        }
    }
}

// DiagnosticsTabScreen ported in Screens/DiagnosticsTabScreen.swift.
// MenuTabScreen ported in Screens/MenuTabScreen.swift.

// MARK: - Sub-page stubs (Pairing, Calib, Upload, Download, Chatbot, Pin, BleError)

public struct PairingScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            StubCard(title: "Pairing") {
                Text("// TODO: port PairingScreen.kt (362 lines)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
            }
        }
    }
}

// CalibScreen ported in Screens/CalibScreen.swift.

public struct UploadScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            StubCard(title: "Firmware Upload") {
                Text("Picked file: \(vm.state.pickedFileName ?? "—")")
                Text("Progress: \(Int(vm.state.uploadProgress * 100))%")
                Text("// TODO: port UploadScreen.kt (229 lines)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
            }
        }
    }
}

public struct DataDownloadScreen: View {
    @ObservedObject var vm: AppViewModel
    public var body: some View {
        ScrollView {
            StubCard(title: "Data Download") {
                Text("Stage: \(vm.state.dataFilesStage.rawValue)")
                Text("Saved files: \(vm.state.savedDataFiles.count)")
                Text("// TODO: port DataDownloadScreen.kt (390 lines)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
            }
        }
    }
}

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

public struct PinScreen: View {
    public let showBack: Bool
    public let onPinEntered: (Int) -> Void
    public let onBack: () -> Void

    @State private var input: String = ""

    public init(showBack: Bool, onPinEntered: @escaping (Int) -> Void, onBack: @escaping () -> Void) {
        self.showBack = showBack
        self.onPinEntered = onPinEntered
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    if showBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundStyle(AppColors.darkText)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()
                Text("Enter PIN")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                TextField("0000", text: $input)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 32, weight: .bold))
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(AppColors.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: {
                    let pin = Int(input) ?? -1
                    onPinEntered(pin)
                }) {
                    Text("Submit")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: 200)
                        .padding(.vertical, 12)
                        .background(AppColors.primary)
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Text("// TODO: port PinScreen.kt (187 lines)")
                    .font(.caption).foregroundStyle(AppColors.grayLabel)
                Spacer()
            }
        }
    }
}
