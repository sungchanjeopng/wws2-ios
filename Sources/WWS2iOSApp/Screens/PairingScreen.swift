// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/PairingScreen.kt
//
// iOS does NOT need separate Bluetooth permission requests like Android (S+).
// Instead Info.plist's NSBluetoothAlwaysUsageDescription is enough — the
// system shows the permission sheet on the first scan attempt automatically.
// We therefore drop the permission/location-services flow entirely and just
// call vm.startScan().

import SwiftUI
import CoreBluetooth
import WWS2Core
import WWS2BLE
#if canImport(UIKit)
import UIKit
#endif

public struct PairingScreen: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject private var scanner: BleScanner
    @State private var showBleDialog: Bool = false
    @State private var bleDialogTitle: String = ""
    @State private var bleDialogMessage: String = ""
    @State private var bleDialogOpensSettings: Bool = false

    public init(vm: AppViewModel) {
        self.vm = vm
        self.scanner = vm.scanner
    }

    /// "Scan Devices" 버튼 핸들러 — Bluetooth 상태에 따라 안내 다이얼로그 표시
    private func handleScanTap() {
        switch scanner.managerState {
        case .poweredOn:
            vm.startScan()
        case .poweredOff:
            bleDialogTitle = "Bluetooth 꺼짐"
            bleDialogMessage = "BLE 스캔을 위해 Bluetooth를 켜야 합니다.\n제어센터 또는 설정에서 Bluetooth를 켜 주세요."
            bleDialogOpensSettings = true
            showBleDialog = true
        case .unauthorized:
            bleDialogTitle = "Bluetooth 권한 필요"
            bleDialogMessage = "BLE 스캔이 차단되어 있습니다.\n설정 → 앱 → Bluetooth를 허용해 주세요."
            bleDialogOpensSettings = true
            showBleDialog = true
        case .unsupported:
            bleDialogTitle = "지원되지 않음"
            bleDialogMessage = "이 기기는 BLE를 지원하지 않습니다."
            bleDialogOpensSettings = false
            showBleDialog = true
        case .resetting, .unknown:
            // 시스템이 초기화 중 — 사용자가 곧 재시도 가능
            vm.startScan()
        @unknown default:
            vm.startScan()
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScanPanel(
                    isScanning: scanner.isScanning,
                    connectedCount: vm.state.connectedDevices.count
                )

                if vm.state.connectedDevices.count >= 4 {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.primary)
                        Text("4 devices connected. Scanning continues for nearby devices.")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.grayLabel)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                deviceGroups()

                if scanner.isScanning {
                    Text("Scanning continues while this page is open.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.grayLabel)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: { handleScanTap() }) {
                        Text("Scan Devices")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .alert(bleDialogTitle, isPresented: $showBleDialog) {
            if bleDialogOpensSettings {
                Button("설정 열기") { openSettings() }
                Button("취소", role: .cancel) { }
            } else {
                Button("확인", role: .cancel) { }
            }
        } message: {
            Text(bleDialogMessage)
        }
    }

    @ViewBuilder
    private func deviceGroups() -> some View {
        let scanned = scanner.scannedDevices

        // Strip the "_CH1"/"_CH2" suffix from connected ids to match scanned addresses.
        let connectedAddrs: Set<String> = Set(
            vm.state.connectedDevices.map { device -> String in
                let s = device.id
                if let r = s.range(of: "_CH") { return String(s[..<r.lowerBound]) }
                return s
            }
        )

        let unconnected = scanned.values
            .filter { !connectedAddrs.contains($0.address) }
            .sorted { $0.rssi > $1.rssi }

        let interfaceDevices = unconnected.filter { isInterfaceName($0) }
        let densityDevices = unconnected.filter { !isInterfaceName($0) }

        let connectedInterface = vm.state.connectedDevices.filter {
            $0.label.uppercased().hasPrefix("ENV130") || $0.deviceType == 1
        }
        let connectedDensity = vm.state.connectedDevices.filter {
            !($0.label.uppercased().hasPrefix("ENV130") || $0.deviceType == 1)
        }

        VStack(spacing: 14) {
            DeviceGroupSection(title: "ENV130") {
                DeviceSubSection(
                    label: "Connected",
                    count: connectedInterface.count,
                    countSuffix: "active",
                    emptyText: "No connected devices."
                ) {
                    ForEach(connectedInterface, id: \.id) { device in
                        DeviceCard(
                            name: device.label,
                            signalLevel: scanner.signalLevel(rssi: scanned[device.id]?.rssi ?? -70),
                            isConnected: true,
                            isSelected: device.id == vm.state.activeDeviceId,
                            onTap: { vm.requestConnectDevice(device.id) },
                            onDisconnectTap: { vm.disconnectDevice(device.id) }
                        )
                    }
                }
                DeviceSubSection(
                    label: "Scanned",
                    count: interfaceDevices.count,
                    countSuffix: "found",
                    emptyText: scanner.isScanning
                        ? "Searching for ENV130 devices..."
                        : "No ENV130 devices found."
                ) {
                    ForEach(interfaceDevices, id: \.address) { device in
                        DeviceCard(
                            name: device.name,
                            signalLevel: scanner.signalLevel(rssi: device.rssi),
                            isConnecting: vm.state.connectingIds.contains(device.address),
                            onTap: { vm.requestConnectDevice(device.address) }
                        )
                    }
                }
            }

            DeviceGroupSection(title: "ENV230") {
                DeviceSubSection(
                    label: "Connected",
                    count: connectedDensity.count,
                    countSuffix: "active",
                    emptyText: "No connected devices."
                ) {
                    ForEach(connectedDensity, id: \.id) { device in
                        DeviceCard(
                            name: device.label,
                            signalLevel: scanner.signalLevel(rssi: scanned[device.id]?.rssi ?? -70),
                            isConnected: true,
                            isSelected: device.id == vm.state.activeDeviceId,
                            onTap: { vm.requestConnectDevice(device.id) },
                            onDisconnectTap: { vm.disconnectDevice(device.id) }
                        )
                    }
                }
                DeviceSubSection(
                    label: "Scanned",
                    count: densityDevices.count,
                    countSuffix: "found",
                    emptyText: scanner.isScanning
                        ? "Searching for ENV230 devices..."
                        : "No ENV230 devices found."
                ) {
                    ForEach(densityDevices, id: \.address) { device in
                        DeviceCard(
                            name: device.name,
                            signalLevel: scanner.signalLevel(rssi: device.rssi),
                            isConnecting: vm.state.connectingIds.contains(device.address),
                            onTap: { vm.requestConnectDevice(device.address) }
                        )
                    }
                }
            }
        }
    }

    private func isInterfaceName(_ d: ScannedDevice) -> Bool {
        let raw = d.rawName.uppercased()
        let name = d.name.uppercased()
        return raw.hasPrefix("W3") || raw.contains("ENV130") || name.hasPrefix("ENV130")
    }
}

private struct ScanPanel: View {
    let isScanning: Bool
    let connectedCount: Int
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.08))
                    .frame(width: 48, height: 48)
                if isScanning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.primary)
                }
                Image(systemName: "wave.3.right")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.primary)
            }
            Text(isScanning ? "Scanning nearby devices" : "Pair BLE devices")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.darkText)
            Text(isScanning
                 ? "Tap a device card to connect after PIN entry."
                 : "Use Scan Devices to find nearby BLE devices.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.grayLabel)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text(isScanning ? "Scanning..." : "Ready to scan")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isScanning ? AppColors.primary : AppColors.grayLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isScanning ? AppColors.primary.opacity(0.1) : AppColors.background)
                    .clipShape(Capsule())
                Text("\(connectedCount)/4 Connected")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.background)
                    .clipShape(Capsule())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
    }
}

private struct DeviceGroupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(AppColors.darkText)
                .padding(.bottom, 4)
                .padding(.leading, 2)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: AppColors.cardShadow, radius: 3, y: 2)
    }
}

private struct DeviceSubSection<Content: View>: View {
    let label: String
    let count: Int
    let countSuffix: String
    let emptyText: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                Spacer()
                Text("\(count) \(countSuffix)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.weakText)
            }
            .padding(.horizontal, 2)

            if count == 0 {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.grayLabel)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.lightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                content()
            }
        }
    }
}
