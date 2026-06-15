// Shared Android-parity routing helpers used by the SwiftUI app and XCTest.
//
// The Android MainViewModel treats interface meters as one physical BLE link
// with one or two virtual app devices: `<address>_CH1` and `<address>_CH2`.
// Keep that mapping outside AppViewModel so the no-iPhone CI tests can lock
// down the command/page-index behaviour.

import Foundation

public enum DeviceRouting {

    public struct ConnectedBuildResult: Equatable, Sendable {
        public let devices: [ConnectedBleDevice]
        public let visibleDeviceIds: Set<String>
        public let activeDeviceId: String
        public let activeDeviceLabel: String
        public let deviceType: DeviceType

        public init(
            devices: [ConnectedBleDevice],
            visibleDeviceIds: Set<String>,
            activeDeviceId: String,
            activeDeviceLabel: String,
            deviceType: DeviceType
        ) {
            self.devices = devices
            self.visibleDeviceIds = visibleDeviceIds
            self.activeDeviceId = activeDeviceId
            self.activeDeviceLabel = activeDeviceLabel
            self.deviceType = deviceType
        }
    }

    public static func buildConnectedDevices(
        address: String,
        scanned: ScannedDevice?,
        pairingDeviceInfo: DeviceInfo?,
        usedLabels: Set<String>
    ) -> ConnectedBuildResult {
        let repo = DeviceRepository()
        let bleName = scanned?.rawName.isEmpty == false ? scanned?.rawName ?? "" : scanned?.name ?? ""
        let isInterface = DeviceRepository.isInterfaceMeter(name: bleName)
        let firmwareVersion = firmwareVersion(from: pairingDeviceInfo, scanned: scanned, bleName: bleName, repo: repo)

        if isInterface {
            let ch1Id = "\(address)_CH1"
            let ch2Id = "\(address)_CH2"
            let allocated = repo.allocateInterfaceLabels(usedLabels: usedLabels)
            let ch1Site = scanned?.ch1SiteName ?? ""
            let ch2Site = scanned?.ch2SiteName ?? ""
            let ch1Label = ch1Site.isEmpty ? allocated.0 : "ENV130_\(ch1Site)"

            var devices = [
                ConnectedBleDevice(
                    id: ch1Id,
                    label: ch1Label,
                    firmwareVersion: firmwareVersion,
                    deviceType: 1
                )
            ]

            if !ch2Site.isEmpty {
                devices.append(
                    ConnectedBleDevice(
                        id: ch2Id,
                        label: "ENV130_\(ch2Site)",
                        firmwareVersion: firmwareVersion,
                        deviceType: 1
                    )
                )
            }

            return ConnectedBuildResult(
                devices: devices,
                visibleDeviceIds: Set(devices.map(\.id)),
                activeDeviceId: ch1Id,
                activeDeviceLabel: ch1Label,
                deviceType: .interface_
            )
        }

        let pairingSite = siteName(from: pairingDeviceInfo)
        let advertisedSite = scanned?.ch1SiteName ?? ""
        let label: String
        if !pairingSite.isEmpty {
            label = "ENV230_\(pairingSite)"
        } else if !advertisedSite.isEmpty {
            label = "ENV230_\(advertisedSite)"
        } else {
            label = repo.allocateDensityLabel(usedLabels: usedLabels)
        }

        let device = ConnectedBleDevice(
            id: address,
            label: label,
            firmwareVersion: firmwareVersion,
            deviceType: 0
        )
        return ConnectedBuildResult(
            devices: [device],
            visibleDeviceIds: [address],
            activeDeviceId: address,
            activeDeviceLabel: label,
            deviceType: .density
        )
    }

    public static func heartbeatPageIndex(
        tabIndex: Int,
        subPage: String?,
        activeDeviceId: String,
        deviceType: DeviceType,
        echoMode: EchoMode
    ) -> UInt16 {
        let isCh2 = isCh2DeviceId(activeDeviceId)

        if tabIndex == 4 {
            switch subPage {
            case "pairing":
                return Command.pagePairing
            case "download":
                return isCh2 ? Command.pageDownloadCh2 : Command.pageDownload
            case "upload":
                return Command.pageUpload
            case "calib":
                return Command.pageCalib
            default:
                return Command.pageMenu
            }
        }

        if tabIndex == 3 {
            return isCh2 ? Command.pageStatusCh2 : Command.pageStatus
        }

        switch tabIndex {
        case 0:
            return isCh2 ? Command.pageStatusCh2 : Command.pageStatus
        case 1:
            let isInterfaceAvg = echoMode == .avg && deviceType == .interface_
            if isCh2 {
                return isInterfaceAvg ? Command.pageEchoAvgCh2 : Command.pageEchoCh2
            }
            return isInterfaceAvg ? Command.cmdIfEchoAvg : Command.pageEcho
        case 2:
            return isCh2 ? Command.pageStatusCh2 : Command.pageStatus
        default:
            return UInt16(max(tabIndex, 0))
        }
    }

    public static func physicalDeviceId(for deviceId: String) -> String {
        if deviceId.hasSuffix("_CH1") || deviceId.hasSuffix("_CH2") {
            return String(deviceId.dropLast(4))
        }
        return deviceId
    }

    public static func isCh2DeviceId(_ deviceId: String) -> Bool {
        deviceId.hasSuffix("_CH2")
    }

    public static func isInterfaceCh2Command(_ cmd: UInt16) -> Bool {
        switch cmd {
        case Command.cmdStatusCh2,
             Command.cmdEchoCh2,
             Command.cmdTrendCh2,
             Command.cmdDiagCh2,
             Command.cmdIfEchoAvgCh2,
             Command.cmdDownloadCh2,
             Command.cmdDownloadCancelCh2:
            return true
        default:
            return false
        }
    }

    public static func isInterfaceEchoCommand(_ cmd: UInt16) -> Bool {
        switch cmd {
        case Command.cmdIfEchoReal,
             Command.cmdEchoCh2,
             Command.cmdIfEchoAvg,
             Command.cmdIfEchoAvgCh2:
            return true
        default:
            return false
        }
    }

    public static func downloadCommand(for deviceId: String) -> UInt16 {
        isCh2DeviceId(deviceId) ? Command.cmdDownloadCh2 : Command.cmdDownload
    }

    public static func logicalDeviceId(
        physicalId: String,
        cmd: UInt16,
        connectedDeviceIds: Set<String>
    ) -> String {
        let physical = physicalDeviceId(for: physicalId)
        if connectedDeviceIds.contains(physical) {
            return physical
        }

        let ch1Id = "\(physical)_CH1"
        let ch2Id = "\(physical)_CH2"
        if isInterfaceCh2Command(cmd), connectedDeviceIds.contains(ch2Id) {
            return ch2Id
        }
        if connectedDeviceIds.contains(ch1Id) {
            return ch1Id
        }
        return physical
    }

    private static func firmwareVersion(
        from info: DeviceInfo?,
        scanned: ScannedDevice?,
        bleName: String,
        repo: DeviceRepository
    ) -> String {
        if let info {
            // Paired successfully. If the firmware reported a version, use it;
            // otherwise it predates BLE version reporting (added in v1.1.2).
            // In that case show nothing rather than a guessed value.
            if let fw = info.fwVersion {
                return fw.description
            }
            return ""
        }
        if let scanned, !scanned.fwVersion.isEmpty {
            return scanned.fwVersion
        }
        return repo.extractFirmwareVersion(bleName: bleName)
    }

    private static func siteName(from info: DeviceInfo?) -> String {
        guard let info,
              let scalar = String(info.siteNameHi).unicodeScalars.first else { return "" }
        let code = scalar.value
        guard code >= 65, code <= 90, info.siteNameLo >= 0, info.siteNameLo <= 99 else {
            return ""
        }
        return "\(String(scalar))\(String(format: "%02d", info.siteNameLo))"
    }
}
