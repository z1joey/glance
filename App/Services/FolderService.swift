import Foundation

enum FolderServiceError: Error, Equatable {
    case notADirectory
    case ioFailure(String)
}

/// Stateless top-level folder listing.
enum FolderService {

    static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// The folder's top-level `.md`/`.markdown` files, sorted by name
    /// (Finder-style, numeric-aware).
    static func markdownFiles(in folder: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FolderServiceError.notADirectory
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        return contents
            .filter { markdownExtensions.contains($0.pathExtension.lowercased()) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}
