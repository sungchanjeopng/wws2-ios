// Ported from app/src/main/java/com/wws2/densitymeter/model/DataFileItem.kt
//
// Original Kotlin allowed `allRecords = chartRecords` as a default value
// referencing another constructor parameter. Swift does not permit defaults
// that depend on other parameters, so we provide two initializers instead:
// one with both lists (full control), one with a single list (mirrors the
// "default" branch).

public struct DataFileItem: Equatable, Hashable, Sendable {
    public let name: String
    public let recordCount: Int
    public let rangeLabel: String
    public let sizeBytes: Int
    public let targetDevice: String
    public let chartRecords: [TrendRecord]
    public let allRecords: [TrendRecord]

    public init(
        name: String,
        recordCount: Int,
        rangeLabel: String,
        sizeBytes: Int,
        targetDevice: String,
        chartRecords: [TrendRecord],
        allRecords: [TrendRecord]
    ) {
        self.name = name
        self.recordCount = recordCount
        self.rangeLabel = rangeLabel
        self.sizeBytes = sizeBytes
        self.targetDevice = targetDevice
        self.chartRecords = chartRecords
        self.allRecords = allRecords
    }

    /// Convenience initializer matching the Kotlin default `allRecords = chartRecords`.
    public init(
        name: String,
        recordCount: Int,
        rangeLabel: String,
        sizeBytes: Int,
        targetDevice: String,
        chartRecords: [TrendRecord]
    ) {
        self.init(
            name: name,
            recordCount: recordCount,
            rangeLabel: rangeLabel,
            sizeBytes: sizeBytes,
            targetDevice: targetDevice,
            chartRecords: chartRecords,
            allRecords: chartRecords
        )
    }
}
