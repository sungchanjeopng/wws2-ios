// Ported from app/src/main/java/com/wws2/densitymeter/model/ScannedDevice.kt

public struct ScannedDevice: Equatable, Hashable, Identifiable, Codable, Sendable {
    public let address: String
    public let name: String
    /// 원본 BLE 이름 (AT+MANUF)
    public let rawName: String
    public let rssi: Int
    /// AT+ADVDATA 원본
    public let advData: String
    /// 파싱된 CH1 기기번호 (예: "A01")
    public let ch1SiteName: String
    /// 파싱된 CH2 기기번호 (예: "A02", 없으면 "")
    public let ch2SiteName: String
    /// 파싱된 FW 버전 (예: "1.0.9")
    public let fwVersion: String

    public var id: String { address }

    public init(
        address: String,
        name: String,
        rawName: String = "",
        rssi: Int,
        advData: String = "",
        ch1SiteName: String = "",
        ch2SiteName: String = "",
        fwVersion: String = ""
    ) {
        self.address = address
        self.name = name
        self.rawName = rawName
        self.rssi = rssi
        self.advData = advData
        self.ch1SiteName = ch1SiteName
        self.ch2SiteName = ch2SiteName
        self.fwVersion = fwVersion
    }
}
