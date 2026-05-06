// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/MainShellScreen.kt
//
// Top-level container: TopBar + active tab/sub-page + BottomNavBar.
// Sub-page priority over the tab itself (matches the Compose `when` ladder).

import SwiftUI

public struct MainShellView: View {
    @StateObject private var vm = AppViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(
                    isConnected: vm.isConnected,
                    statusLabel: vm.statusLabel,
                    title: vm.currentTitle,
                    showBack: vm.state.tabIndex == 4 && vm.state.subPage != nil,
                    rxBlink: vm.state.rxBlink,
                    aiActive: false,
                    onBackTap: { vm.handleTopBarBack() },
                    onBleTap: { vm.openPairing() },
                    onChatTap: { vm.openChatbot() }
                )

                bodyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.background)

                BottomNavBar(
                    currentIndex: vm.state.tabIndex,
                    onTap: { vm.setTab($0) }
                )
            }

            // Full-screen PIN overlay for pairing
            if vm.showPinForPairing {
                PinScreen(
                    showBack: true,
                    onPinEntered: { vm.onPairingPinResult($0) },
                    onBack: { vm.onPairingPinResult(-1) }
                )
                .transition(.opacity)
            }
        }
        .alert(item: $vm.bleError) { err in
            // SwiftUI Alert (replaces Compose BleErrorDialog)
            // Note: BleErrorState needs Identifiable conformance in AppViewModel
            // — will be added when wiring BLE flow.
            return Alert(
                title: Text("BLE Error"),
                message: Text(err.message),
                primaryButton: .default(Text("Retry"), action: { vm.retryBleError() }),
                secondaryButton: .cancel(Text("Dismiss"), action: { vm.dismissBleError() })
            )
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if vm.state.tabIndex == 4, let sub = vm.state.subPage {
            switch sub {
            case "pairing":  PairingScreen(vm: vm)
            case "calib":    CalibScreen(vm: vm)
            case "upload":   UploadScreen(vm: vm)
            case "chatbot":  ChatbotScreen(vm: vm)
            case "download": DataDownloadScreen(vm: vm)
            default:         MenuTabScreen(vm: vm)
            }
        } else {
            switch vm.state.tabIndex {
            case 0: MainTabScreen(vm: vm)
            case 1: EchoTabScreen(vm: vm)
            case 2: TrendTabScreen(vm: vm)
            case 3: DiagnosticsTabScreen(vm: vm)
            case 4: MenuTabScreen(vm: vm)
            default: MainTabScreen(vm: vm)
            }
        }
    }
}

// Make BleErrorState identifiable for SwiftUI .alert(item:)
extension BleErrorState: Identifiable {
    public var id: String { retryAddress + message }
}
