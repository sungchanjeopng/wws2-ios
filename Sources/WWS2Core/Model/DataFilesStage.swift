// Ported from app/src/main/java/com/wws2/densitymeter/model/DataFilesStage.kt
//
// Original Kotlin:
//   enum class DataFilesStage { LIST, DOWNLOADING, COMPLETE, VIEW, ERROR }

public enum DataFilesStage: String, CaseIterable, Codable, Sendable {
    case list        = "LIST"
    case downloading = "DOWNLOADING"
    case complete    = "COMPLETE"
    case view        = "VIEW"
    case error       = "ERROR"
}
