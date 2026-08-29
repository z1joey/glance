import Foundation

enum FileServiceError: Error, Equatable {
    case notFound
    case invalidUTF8
    case tooLarge
    case unwritable
    case writeConflict
    case ioFailure(String)
}

struct LoadedFile: Equatable {
    let text: String
    let modificationDate: Date
}

/// Stateless file I/O with Glance's guards: strict UTF-8, 20 MB cap, and
/// save-time mtime conflict detection. Non-isolated `async` functions run off
/// the main actor.
enum FileService {

    static let maxFileSizeBytes = 20 * 1024 * 1024

    /// Modification-date tolerance for conflict detection. APFS (macOS 13+,
    /// this app's floor) stamps mtimes with nanosecond precision, so a tight
    /// tolerance is correct — a loose one would miss foreign edits made
    /// shortly after a file was opened. Sub-tolerance granularity only
    /// matters on legacy HFS+/FAT volumes.
    static let mtimeTolerance: TimeInterval = 0.01

    static func load(at url: URL) async throws -> LoadedFile {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw FileServiceError.notFound
        }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxFileSizeBytes else {
            throw FileServiceError.tooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FileServiceError.ioFailure(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileServiceError.invalidUTF8
        }
        let modificationDate = (attrs[.modificationDate] as? Date) ?? Date()
        return LoadedFile(text: text, modificationDate: modificationDate)
    }

    /// Write `text` only if the file's mtime still matches `modificationDate`
    /// (pass nil to skip the check). Returns the post-write modification date.
    static func save(_ text: String, to url: URL, expecting modificationDate: Date?) async throws -> Date {
        if let expected = modificationDate {
            guard let current = currentModificationDate(of: url),
                  abs(current.timeIntervalSince(expected)) <= mtimeTolerance else {
                throw FileServiceError.writeConflict
            }
        }
        return try await write(text, to: url)
    }

    /// Write unconditionally (used to resolve a detected conflict as
    /// "Overwrite").
    static func overwrite(_ text: String, to url: URL) async throws -> Date {
        try await write(text, to: url)
    }

    static func isWritable(at url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    static func currentModificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private static func write(_ text: String, to url: URL) async throws -> Date {
        guard isWritable(at: url) else {
            throw FileServiceError.unwritable
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FileServiceError.ioFailure(error.localizedDescription)
        }
        return currentModificationDate(of: url) ?? Date()
    }
}
