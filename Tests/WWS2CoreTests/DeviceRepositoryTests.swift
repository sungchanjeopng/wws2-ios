import XCTest
@testable import WWS2Core

final class DeviceRepositoryTests: XCTestCase {

    private final class StubSession: BleSession {
        var disconnectCount = 0
        func disconnect() { disconnectCount += 1 }
    }

    func testSetGetRemove() {
        let repo = DeviceRepository()
        let s1 = StubSession()
        let s2 = StubSession()
        repo.setSession(deviceId: "a", session: s1)
        repo.setSession(deviceId: "b", session: s2)
        XCTAssertTrue(repo.getSession(deviceId: "a") === s1)
        XCTAssertTrue(repo.getSession(deviceId: "b") === s2)
        repo.removeSession(deviceId: "a")
        XCTAssertNil(repo.getSession(deviceId: "a"))
        XCTAssertTrue(repo.getSession(deviceId: "b") === s2)
    }

    func testRemoveSessionsBulk() {
        let repo = DeviceRepository()
        for id in ["a", "b", "c"] {
            repo.setSession(deviceId: id, session: StubSession())
        }
        repo.removeSessions(ids: ["a", "c"])
        XCTAssertNil(repo.getSession(deviceId: "a"))
        XCTAssertNil(repo.getSession(deviceId: "c"))
        XCTAssertNotNil(repo.getSession(deviceId: "b"))
    }

    func testDisconnectAllCallsDisconnectAndClears() {
        let repo = DeviceRepository()
        let s1 = StubSession(); let s2 = StubSession()
        repo.setSession(deviceId: "a", session: s1)
        repo.setSession(deviceId: "b", session: s2)
        repo.disconnectAll()
        XCTAssertEqual(s1.disconnectCount, 1)
        XCTAssertEqual(s2.disconnectCount, 1)
        XCTAssertNil(repo.getSession(deviceId: "a"))
    }

    func testAllocateDensityLabelSequential() {
        let repo = DeviceRepository()
        XCTAssertEqual(repo.allocateDensityLabel(usedLabels: []), "ENV230_A01")
        XCTAssertEqual(repo.allocateDensityLabel(usedLabels: ["ENV230_A01"]), "ENV230_A02")
        XCTAssertEqual(
            repo.allocateDensityLabel(usedLabels: ["ENV230_A01", "ENV230_A02", "ENV230_A03"]),
            "ENV230_A04"
        )
        // All taken — falls back to A04 (matches Kotlin)
        XCTAssertEqual(
            repo.allocateDensityLabel(usedLabels: ["ENV230_A01", "ENV230_A02", "ENV230_A03", "ENV230_A04"]),
            "ENV230_A04"
        )
    }

    func testAllocateInterfaceLabelsPairs() {
        let repo = DeviceRepository()
        let p1 = repo.allocateInterfaceLabels(usedLabels: [])
        XCTAssertEqual(p1.0, "ENV130_A02")
        XCTAssertEqual(p1.1, "ENV130_A03")

        let p2 = repo.allocateInterfaceLabels(usedLabels: ["ENV130_A02"])
        XCTAssertEqual(p2.0, "ENV130_A04")
        XCTAssertEqual(p2.1, "ENV130_A05")

        // Fallback to first pair when nothing fits
        let p3 = repo.allocateInterfaceLabels(usedLabels: [
            "ENV130_A02", "ENV130_A04", "ENV130_A06", "ENV130_A08"
        ])
        XCTAssertEqual(p3.0, "ENV130_A02")
        XCTAssertEqual(p3.1, "ENV130_A03")
    }

    func testExtractFirmwareVersionMatchesKotlinRegex() {
        let repo = DeviceRepository()
        XCTAssertEqual(repo.extractFirmwareVersion(bleName: "WESS_V0.1_ENV230_A01"), "V0.1")
        XCTAssertEqual(repo.extractFirmwareVersion(bleName: "v1.23_dev"), "v1.23")   // case-insensitive
        XCTAssertEqual(repo.extractFirmwareVersion(bleName: "no version here"), "")
    }

    func testIsInterfaceMeterDetection() {
        XCTAssertTrue(DeviceRepository.isInterfaceMeter(name: "W3_A01_A02"))
        XCTAssertTrue(DeviceRepository.isInterfaceMeter(name: "ENV130_A02"))
        XCTAssertTrue(DeviceRepository.isInterfaceMeter(name: "we13_test"))
        XCTAssertTrue(DeviceRepository.isInterfaceMeter(name: "INTERFACE_DEV"))
        XCTAssertFalse(DeviceRepository.isInterfaceMeter(name: "W2_A01"))
        XCTAssertFalse(DeviceRepository.isInterfaceMeter(name: "ENV230_A01"))
    }
}
