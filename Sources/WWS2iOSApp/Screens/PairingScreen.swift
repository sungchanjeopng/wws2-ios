// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/PairingScreen.kt
//
// iOS does NOT need separate Bluetooth permission requests like Android (S+).
// Instead Info.plist's NSBluetoothAlwaysUsageDescription is enough — the
// system shows the permission sheet on the first scan attempt automatically.
// We therefore drop the permission/location-services flow entirely and just
// call vm.startScan().

import SwiftUI
import WWS2Core

public struct PairingScreen: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject private var scanner: BleScanner

    public init(vm: AppViewModel) {
        self.vm = vm
        self.scanner = vm.scanner
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
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.primary)
                        Text("4 devices connected. Scanning continues for nearby devices.")
                            .font(.system(size: 13))
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
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.grayLabel)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: { vm.startScan() }) {
                        Text("Scan Devices")
                            .font(.system(size: 22, weight: .bold))
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
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.primary)
            }
            Text(isScanning ? "Scanning nearby devices" : "Pair BLE devices")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.darkText)
            Text(isScanning
                 ? "Tap a device card to connect after PIN entry."
                 : "Use Scan Devices to find nearby BLE devices.")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.grayLabel)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text(isScanning ? "Scanning..." : "Ready to scan")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isScanning ? AppColors.primary : AppColors.grayLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isScanning ? AppColors.primary.opacity(0.1) : AppColors.background)
                    .clipShape(Capsule())
                Text("\(connectedCount)/4 Connected")
                    .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 18, weight: .heavy))
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                Spacer()
                Text("\(count) \(countSuffix)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.weakText)
            }
            .padding(.horizontal, 2)

            if count == 0 {
                Text(emptyText)
                    .font(.system(size: 13))
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
