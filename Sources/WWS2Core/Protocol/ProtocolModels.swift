// Ported from app/src/main/java/com/wws2/densitymeter/ble/protocol/ProtocolModels.kt
//
// Data types used in the BLE protocol layer.

import Foundation

public struct FwVersion: Equatable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func fromBytes(major: Int, minor: Int, patch: Int) -> FwVersion {
        FwVersion(major: major, minor: minor, patch: patch)
    }
}

extension FwVersion: CustomStringConvertible {
    public var description: String { "v\(major).\(minor).\(patch)" }
}

public struct DeviceInfo: Equatable, Hashable, Sendable {
    public let siteNameHi: Character
    public let siteNameLo: Int
    public let ch2SiteNameHi: Character
    public let ch2SiteNameLo: Int
    /// Firmware version reported in the pairing response. `nil` when the
    /// device did not include version bytes — i.e. firmware older than v1.1.2,
    /// where BLE version reporting was introduced.
    public let fwVersion: FwVersion?

    public init(
        siteNameHi: Character,
        siteNameLo: Int,
        ch2SiteNameHi: Character = "\u{0000}",
        ch2SiteNameLo: Int = 0,
        fwVersion: FwVersion?
    ) {
        self.siteNameHi = siteNameHi
        self.siteNameLo = siteNameLo
        self.ch2SiteNameHi = ch2SiteNameHi
        self.ch2SiteNameLo = ch2SiteNameLo
        self.fwVersion = fwVersion
    }
}

public enum PairingResult: Equatable, Sendable {
    case success(DeviceInfo)
    case pinFailed
}

public struct ParsedFrame: Equatable, Hashable, Sendable {
    public let cmd: UInt16
    public let data: [UInt8]

    public init(cmd: UInt16, data: [UInt8]) {
        self.cmd = cmd
        self.data = data
    }
}
