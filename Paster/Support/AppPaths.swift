import Foundation

struct AppPaths: Equatable, Sendable {
    enum PathError: Error {
        case applicationSupportDirectoryUnavailable
    }

    let applicationSupportDirectory: URL
    let databaseURL: URL
    let blobsDirectory: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil
    ) throws {
        let supportRoot: URL
        if let applicationSupportRoot {
            supportRoot = applicationSupportRoot
        } else if let systemSupportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            supportRoot = systemSupportRoot
        } else {
            throw PathError.applicationSupportDirectoryUnavailable
        }

        applicationSupportDirectory = supportRoot.appendingPathComponent(
            AppConfiguration.bundleIdentifier,
            isDirectory: true
        )
        databaseURL = applicationSupportDirectory.appendingPathComponent(
            "clips.sqlite",
            isDirectory: false
        )
        blobsDirectory = applicationSupportDirectory.appendingPathComponent(
            "blobs",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: blobsDirectory,
            withIntermediateDirectories: true
        )
    }
}
