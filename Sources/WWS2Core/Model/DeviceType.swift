// Ported from app/src/main/java/com/wws2/densitymeter/model/DeviceType.kt
//
// Original Kotlin:
//   enum class DeviceType { DENSITY, INTERFACE }

public enum DeviceType: String, CaseIterable, Codable, Sendable {
    case density = "DENSITY"
    case interface_ = "INTERFACE"
}
