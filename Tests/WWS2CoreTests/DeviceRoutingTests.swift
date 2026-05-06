import XCTest
@testable import WWS2Core

final class DeviceRoutingTests: XCTestCase {

    func testBuildInterfaceDualChannelDevicesCreatesAndroidStyleVirtualIds() {
        let scanned = ScannedDevice(
            address: "peripheral-1",
            name: "ENV130  A01 / A02",
            rawName: "W3A01A02",
            rssi: -45,
            ch1SiteName: "A01",
            ch2SiteName: "A02"
        )

        let result = DeviceRouting.buildConnectedDevices(
            address: "peripheral-1",
            scanned: scanned,
            pairingDeviceInfo: nil,
            usedLabels: []
        )

        XCTAssertEqual(result.deviceType, .interface_)
        XCTAssertEqual(result.activeDeviceId, "peripheral-1_CH1")
        XCTAssertEqual(result.activeDeviceLabel, "ENV130_A01")
        XCTAssertEqual(result.visibleDeviceIds, Set(["peripheral-1_CH1", "peripheral-1_CH2"]))
        XCTAssertEqual(result.devices, [
            ConnectedBleDevice(id: "peripheral-1_CH1", label: "ENV130_A01", firmwareVersion: "", deviceType: 1),
            ConnectedBleDevice(id: "peripheral-1_CH2", label: "ENV130_A02", firmwareVersion: "", deviceType: 1)
        ])
    }

    func testBuildDensityDeviceUsesPairingSiteNameBeforeAdvertisedSite() {
        let scanned = ScannedDevice(
            address: "density-1",
            name: "ENV230_A01",
            rawName: "W2A01",
            rssi: -55,
            ch1SiteName: "A01"
        )
        let deviceInfo = DeviceInfo(
            siteNameHi: "B",
            siteNameLo: 7,
            fwVersion: FwVersion(major: 1, minor: 2, patch: 3)
        )

        let result = DeviceRouting.buildConnectedDevices(
            address: "density-1",
            scanned: scanned,
            pairingDeviceInfo: deviceInfo,
            usedLabels: []
        )

        XCTAssertEqual(result.deviceType, .density)
        XCTAssertEqual(result.devices, [
            ConnectedBleDevice(id: "density-1", label: "ENV230_B07", firmwareVersion: "v1.2.3", deviceType: 0)
        ])
        XCTAssertEqual(result.visibleDeviceIds, Set(["density-1"]))
        XCTAssertEqual(result.activeDeviceId, "density-1")
        XCTAssertEqual(result.activeDeviceLabel, "ENV230_B07")
    }

    func testHeartbeatPageIndexMatchesAndroidForCh2AndCalibration() {
        XCTAssertEqual(
            DeviceRouting.heartbeatPageIndex(
                tabIndex: 0,
                subPage: nil,
                activeDeviceId: "peripheral-1_CH2",
                deviceType: .interface_,
                echoMode: .real
            ),
            Command.pageStatusCh2
        )
        XCTAssertEqual(
            DeviceRouting.heartbeatPageIndex(
                tabIndex: 1,
                subPage: nil,
                activeDeviceId: "peripheral-1_CH2",
                deviceType: .interface_,
                echoMode: .avg
            ),
            Command.pageEchoAvgCh2
        )
        XCTAssertEqual(
            DeviceRouting.heartbeatPageIndex(
                tabIndex: 4,
                subPage: "download",
                activeDeviceId: "peripheral-1_CH2",
                deviceType: .interface_,
                echoMode: .real
            ),
            Command.pageDownloadCh2
        )
        XCTAssertEqual(
            DeviceRouting.heartbeatPageIndex(
                tabIndex: 4,
                subPage: "calib",
                activeDeviceId: "density-1",
                deviceType: .density,
                echoMode: .real
            ),
            Command.pageCalib
        )
    }

    func testLogicalDeviceIdRoutesPhysicalNotificationsToVirtualChannel() {
        let connected: Set<String> = ["peripheral-1_CH1", "peripheral-1_CH2"]

        XCTAssertEqual(
            DeviceRouting.logicalDeviceId(
                physicalId: "peripheral-1",
                cmd: Command.cmdStatus,
                connectedDeviceIds: connected
            ),
            "peripheral-1_CH1"
        )
        XCTAssertEqual(
            DeviceRouting.logicalDeviceId(
                physicalId: "peripheral-1",
                cmd: Command.cmdStatusCh2,
                connectedDeviceIds: connected
            ),
            "peripheral-1_CH2"
        )
        XCTAssertEqual(
            DeviceRouting.logicalDeviceId(
                physicalId: "peripheral-1",
                cmd: Command.cmdDownloadCancelCh2,
                connectedDeviceIds: connected
            ),
            "peripheral-1_CH2"
        )
        XCTAssertEqual(
            DeviceRouting.logicalDeviceId(
                physicalId: "density-1",
                cmd: Command.cmdStatus,
                connectedDeviceIds: ["density-1"]
            ),
            "density-1"
        )
    }
}
