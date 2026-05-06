// Ported from app/src/main/java/com/wws2/densitymeter/model/EchoMode.kt
//
// Original Kotlin:
//   enum class EchoMode { REAL, AVG }

public enum EchoMode: String, CaseIterable, Codable, Sendable {
    case real = "REAL"
    case avg = "AVG"
}
