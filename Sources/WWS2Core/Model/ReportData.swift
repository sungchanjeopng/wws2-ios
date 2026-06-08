// Ported from app/src/main/java/com/wws2/densitymeter/model/ReportData.kt

import Foundation

/// 리포트 생성 단계.
public enum ReportStage: Equatable, Sendable {
    case select, collecting, done, error
}

/// 한 ENV130 채널에 대해 리포트 생성 시 BLE 로 수집한 스냅샷.
/// 측정값 + 설정값은 STATUS 응답에서, 파형은 ECHO 실시간/평균 응답에서 모은다.
public struct ReportData: Equatable, Sendable {
    public let deviceId: String
    public let label: String
    public let firmwareVersion: String
    public let timestamp: String
    // 측정값
    public let lightLevel: Double
    public let heavyLevel: Double
    public let temperatureC: Double
    public let currentMA: Double
    // 설정값
    public let freqMHz: Double
    public let offset: Double
    public let emptyDistance: Double
    public let deadZone: Double
    public let set4mA: Double
    public let set20mA: Double
    public let damping: Int
    // 파형
    public let realEcho: InterfaceEchoReading?
    public let avgEcho: InterfaceEchoReading?

    public init(
        deviceId: String, label: String, firmwareVersion: String, timestamp: String,
        lightLevel: Double, heavyLevel: Double, temperatureC: Double, currentMA: Double,
        freqMHz: Double, offset: Double, emptyDistance: Double, deadZone: Double,
        set4mA: Double, set20mA: Double, damping: Int,
        realEcho: InterfaceEchoReading?, avgEcho: InterfaceEchoReading?
    ) {
        self.deviceId = deviceId
        self.label = label
        self.firmwareVersion = firmwareVersion
        self.timestamp = timestamp
        self.lightLevel = lightLevel
        self.heavyLevel = heavyLevel
        self.temperatureC = temperatureC
        self.currentMA = currentMA
        self.freqMHz = freqMHz
        self.offset = offset
        self.emptyDistance = emptyDistance
        self.deadZone = deadZone
        self.set4mA = set4mA
        self.set20mA = set20mA
        self.damping = damping
        self.realEcho = realEcho
        self.avgEcho = avgEcho
    }
}
