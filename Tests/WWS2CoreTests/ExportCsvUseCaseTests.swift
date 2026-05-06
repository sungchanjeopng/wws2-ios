import XCTest
@testable import WWS2Core

final class ExportCsvUseCaseTests: XCTestCase {

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func makeRecord(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int,
                            eeaD: Int, dst: Double, temp: Double, step: Int = 0, vca: Int = 0, status: Int = 0) -> TrendRecord {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        let date = Self.utc.date(from: c)!
        return TrendRecord(dateTime: date, eeaD: eeaD, dst: dst, temperature: temp,
                           step: step, vca: vca, status: status)
    }

    func testDensityCsvHeaderAndRowFormat() {
        let r = makeRecord(year: 2024, month: 3, day: 15, hour: 14, minute: 25, second: 30,
                           eeaD: 100, dst: 12.34, temp: 25.5, step: 7, vca: 42, status: 3)
        let useCase = ExportCsvUseCase(calendar: Self.utc)
        let csv = useCase.buildCsvContent(records: [r], isInterface: false)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.first, "Time,EEA,Density,Temp,Step,VCA,Status")
        XCTAssertEqual(lines[1], "2024-03-15 14:25:30,100,12.34,25.5,7,0.42,3")
    }

    func testInterfaceCsvHeaderAndRowFormat() {
        let r = makeRecord(year: 2024, month: 3, day: 15, hour: 14, minute: 25, second: 30,
                           eeaD: 200, dst: 1.50, temp: -5.5)
        let useCase = ExportCsvUseCase(calendar: Self.utc)
        let csv = useCase.buildCsvContent(records: [r], isInterface: true)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.first, "Time,Light,Heavy,Temp")
        XCTAssertEqual(lines[1], "2024-03-15 14:25:30,1.50,2.00,-5.5")
    }

    func testFormatDateStamp() {
        let r = makeRecord(year: 2024, month: 3, day: 15, hour: 14, minute: 25, second: 30,
                           eeaD: 0, dst: 0, temp: 0)
        let useCase = ExportCsvUseCase(calendar: Self.utc)
        XCTAssertEqual(useCase.formatDateStamp(r.dateTime), "20240315_142530")
    }

    func testSaveAndLoadRoundtrip() throws {
        // Use a temp Documents subfolder per-test to avoid colliding with the
        // production app data path.
        let useCase = ExportCsvUseCase(calendar: Self.utc)
        let r = makeRecord(year: 2024, month: 3, day: 15, hour: 14, minute: 25, second: 30,
                           eeaD: 100, dst: 12.34, temp: 25.5)
        let stamp = useCase.formatDateStamp(r.dateTime)
        let fileName = "ENV230_A01_\(stamp).csv"

        // Sanity: writing the CSV must succeed (returns absolute path).
        let path = useCase.saveCsvToDocuments(fileName: fileName, records: [r], isInterface: false)
        XCTAssertNotNil(path, "saveCsvToDocuments should write the file")
        defer {
            if let p = path { try? FileManager.default.removeItem(atPath: p) }
        }

        // loadSavedFiles should pick our file up.
        let listed = useCase.loadSavedFiles()
        XCTAssertTrue(listed.contains(where: { $0.name == fileName }),
                      "saved file should be discoverable by loadSavedFiles")
        if let info = listed.first(where: { $0.name == fileName }) {
            XCTAssertEqual(info.recordCount, 1)
            XCTAssertEqual(info.targetDevice, "ENV230_A01")
        }
    }
}
