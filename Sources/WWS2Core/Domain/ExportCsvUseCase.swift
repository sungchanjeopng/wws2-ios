// Ported from app/src/main/java/com/wws2/densitymeter/domain/ExportCsvUseCase.kt
//
// CSV export of TrendRecord lists. The Android original uses external Documents
// + FileProvider for share intents. On iOS we use the app's Documents directory
// via FileManager. The CSV string format follows the active Android
// MainViewModel export path used by the app UI.

import Foundation

public struct CsvFileInfo: Equatable, Hashable, Sendable {
    public let name: String
    public let recordCount: Int
    public let rangeLabel: String
    public let sizeBytes: Int
    public let targetDevice: String

    public init(name: String, recordCount: Int, rangeLabel: String, sizeBytes: Int, targetDevice: String) {
        self.name = name
        self.recordCount = recordCount
        self.rangeLabel = rangeLabel
        self.sizeBytes = sizeBytes
        self.targetDevice = targetDevice
    }
}

public final class ExportCsvUseCase {

    /// Calendar/timezone used to format `dateTime` strings in CSV. Defaults to
    /// UTC gregorian to match `TrendRecord.fromBytes` storage. Tests can pass
    /// a fixed locale calendar to make output deterministic.
    public let calendar: Calendar
    public let locale: Locale

    /// Subfolder under Documents/ where CSV files are stored.
    public static let documentsSubfolder = "WESSWARE"

    public init(calendar: Calendar? = nil, locale: Locale = Locale(identifier: "en_US_POSIX")) {
        if let c = calendar {
            self.calendar = c
        } else {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC") ?? .current
            self.calendar = c
        }
        self.locale = locale
    }

    /// Build the CSV body (header + rows) for a list of trend records.
    /// `isInterface=true` produces the 4-column interface-meter format,
    /// otherwise the 7-column density-meter format. Column order, headers,
    /// and decimal precision match the active Kotlin UI export path.
    public func buildCsvContent(records: [TrendRecord], isInterface: Bool) -> String {
        var sb = ""
        if isInterface {
            sb.append("Time,Light,Heavy,Temp\n")
            for r in records {
                let dt = formatDateTime(r.dateTime)
                let line = String(
                    format: "%@,%.2f,%.2f,%.1f\n",
                    dt,
                    r.dst,
                    Double(r.eeaD) * 0.01,
                    r.temperature
                )
                sb.append(line)
            }
        } else {
            sb.append("Time,EEA,Density,Temp,Step,VCA,Status\n")
            for r in records {
                let dt = formatDateTime(r.dateTime)
                let line = String(
                    format: "%@,%d,%.2f,%.1f,%d,%d,%d\n",
                    dt,
                    r.eeaD,
                    r.dst,
                    r.temperature,
                    r.step,
                    r.vca,
                    r.status
                )
                sb.append(line)
            }
        }
        return sb
    }

    /// "yyyy-MM-dd HH:mm:ss" (CSV cell timestamp).
    public func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    /// "yyyyMMdd_HHmmss" (filename-safe stamp).
    public func formatDateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }

    /// Save CSV to `Documents/WESSWARE/<fileName>`. Returns the absolute path
    /// on success or nil on failure. Mirrors Android's saveCsvToDocuments —
    /// the subfolder ("WESSWARE") and file naming are identical.
    @discardableResult
    public func saveCsvToDocuments(fileName: String, records: [TrendRecord], isInterface: Bool) -> String? {
        let csv = buildCsvContent(records: records, isInterface: isInterface)
        return saveCsvText(fileName: fileName, content: csv)
    }

    /// Save raw CSV string. Useful when content was built elsewhere.
    @discardableResult
    public func saveCsvText(fileName: String, content: String) -> String? {
        guard let dir = wesswareDocumentsDirectory() else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            try content.data(using: .utf8)?.write(to: url, options: [.atomic])
            return url.path
        } catch {
            return nil
        }
    }

    /// List CSV files saved under Documents/WESSWARE, sorted by mtime desc.
    /// `rangeLabel` is "<first_time> ~ <last_time>" parsed from the body
    /// (matches Android), or "--" when the file has fewer than 3 lines.
    public func loadSavedFiles() -> [CsvFileInfo] {
        guard let dir = wesswareDocumentsDirectory(),
              FileManager.default.fileExists(atPath: dir.path)
        else { return [] }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let csvFiles = entries.filter { $0.pathExtension.lowercased() == "csv" }

        let sorted = csvFiles.sorted { a, b in
            let ad = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bd = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ad > bd
        }

        return sorted.compactMap { url -> CsvFileInfo? in
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            // Drop trailing empty line that comes from the final '\n'.
            var lines = raw.components(separatedBy: "\n")
            if let last = lines.last, last.isEmpty { lines.removeLast() }
            let recordCount = max(lines.count - 1, 0)
            let rangeLabel: String = {
                guard lines.count >= 3 else { return "--" }
                let firstCol = lines[1].components(separatedBy: ",").first ?? "--"
                let lastCol  = lines.last?.components(separatedBy: ",").first ?? "--"
                return "\(firstCol) ~ \(lastCol)"
            }()
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let baseName = url.deletingPathExtension().lastPathComponent
            // Strip "_20…" suffix to recover the device name (matches
            // Kotlin's substringBefore("_20")).
            let targetDevice: String = {
                if let r = baseName.range(of: "_20") {
                    return String(baseName[..<r.lowerBound])
                }
                return baseName
            }()
            return CsvFileInfo(
                name: url.lastPathComponent,
                recordCount: recordCount,
                rangeLabel: rangeLabel,
                sizeBytes: size,
                targetDevice: targetDevice
            )
        }
    }

    private func wesswareDocumentsDirectory() -> URL? {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls.first?.appendingPathComponent(Self.documentsSubfolder, isDirectory: true)
    }
}
