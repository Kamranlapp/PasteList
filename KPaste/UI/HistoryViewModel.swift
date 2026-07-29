import Combine
import Foundation
import GRDB

actor ClipHistoryActions {
    private let repository: ClipRepository
    private let blobStorage: BlobStorage

    init(repository: ClipRepository, blobStorage: BlobStorage) {
        self.repository = repository
        self.blobStorage = blobStorage
    }

    func setPinned(_ pinned: Bool, for clip: ClipRecord) throws {
        guard let id = clip.id else {
            return
        }
        _ = try repository.setPinned(pinned, for: id)
    }

    func delete(_ clip: ClipRecord) throws {
        guard let id = clip.id else {
            return
        }

        if try repository.delete(id: id) {
            try blobStorage.deleteAll(for: id)
        }
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var pinned: [ClipRecord] = []
    @Published private(set) var history: [ClipRecord] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedClipIDs: [Int64] = []
    @Published var separatorOption: BulkSeparatorOption {
        didSet {
            userDefaults.set(separatorOption.rawValue, forKey: DefaultsKey.separatorOption)
        }
    }
    @Published var customSeparator: String {
        didSet {
            userDefaults.set(customSeparator, forKey: DefaultsKey.customSeparator)
        }
    }
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else {
                return
            }
            startObservation()
        }
    }

    private let repository: ClipRepository
    private let actions: ClipHistoryActions
    private let restorer: ClipRestorer
    private let bulkPasteController: BulkPasteController
    private let onRestored: () -> Void
    private let userDefaults: UserDefaults
    private var selectedClips: [Int64: ClipRecord] = [:]
    private var observation: AnyDatabaseCancellable?

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        restorer: ClipRestorer,
        bulkPasteController: BulkPasteController,
        userDefaults: UserDefaults = .standard,
        onRestored: @escaping () -> Void
    ) {
        self.repository = repository
        actions = ClipHistoryActions(repository: repository, blobStorage: blobStorage)
        self.restorer = restorer
        self.bulkPasteController = bulkPasteController
        self.userDefaults = userDefaults
        self.onRestored = onRestored
        separatorOption = BulkSeparatorOption(
            rawValue: userDefaults.string(forKey: DefaultsKey.separatorOption) ?? ""
        ) ?? .newline
        customSeparator = userDefaults.string(forKey: DefaultsKey.customSeparator) ?? ""
        startObservation()
    }

    var selectedCount: Int { selectedClipIDs.count }

    func canBulkSelect(_ clip: ClipRecord) -> Bool {
        switch ClipContentType(rawValue: clip.type) {
        case .text, .url, .rtf: clip.id != nil
        case .image, .file, nil: false
        }
    }

    func selectionIndex(for clip: ClipRecord) -> Int? {
        guard let id = clip.id, let index = selectedClipIDs.firstIndex(of: id) else {
            return nil
        }
        return index + 1
    }

    func toggleSelection(_ clip: ClipRecord) {
        guard canBulkSelect(clip), let id = clip.id else {
            return
        }
        if let index = selectedClipIDs.firstIndex(of: id) {
            selectedClipIDs.remove(at: index)
            selectedClips[id] = nil
        } else {
            selectedClipIDs.append(id)
            selectedClips[id] = clip
        }
    }

    func replaceSelection(with clips: [ClipRecord]) {
        let selectableClips = clips.filter(canBulkSelect)
        selectedClipIDs = selectableClips.compactMap(\.id)
        selectedClips = Dictionary(
            uniqueKeysWithValues: selectableClips.compactMap { clip in
                clip.id.map { ($0, clip) }
            }
        )
    }

    func clearSelection() {
        selectedClipIDs.removeAll()
        selectedClips.removeAll()
    }

    func pasteSelection() {
        let clips = selectedClipIDs.compactMap { selectedClips[$0] }
        let separator = separatorOption.value(customValue: customSeparator)
        Task {
            do {
                try await bulkPasteController.paste(clips, separator: separator)
                clearSelection()
                onRestored()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pasteSelectionAsIs() {
        let clips = selectedClipIDs.compactMap { selectedClips[$0] }
        Task {
            do {
                try await bulkPasteController.paste(clips, separator: "")
                clearSelection()
                onRestored()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pasteSelection(format: BulkPasteFormat) {
        let clips = selectedClipIDs.compactMap { selectedClips[$0] }
        Task {
            do {
                try await bulkPasteController.paste(clips, format: format)
                clearSelection()
                onRestored()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restore(_ clip: ClipRecord) {
        Task {
            do {
                try await restorer.restore(clip)
                onRestored()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func togglePinned(_ clip: ClipRecord) {
        performAction { [actions] in
            try await actions.setPinned(!clip.pinned, for: clip)
        }
    }

    func delete(_ clip: ClipRecord) {
        if let id = clip.id, let index = selectedClipIDs.firstIndex(of: id) {
            selectedClipIDs.remove(at: index)
            selectedClips[id] = nil
        }
        performAction { [actions] in
            try await actions.delete(clip)
        }
    }

    private enum DefaultsKey {
        static let separatorOption = "bulkPaste.separatorOption"
        static let customSeparator = "bulkPaste.customSeparator"
    }

    private func startObservation() {
        observation?.cancel()
        isLoading = true
        errorMessage = nil

        observation = repository.observeHistory(
            matching: searchText,
            onError: { [weak self] error in
                self?.isLoading = false
                self?.errorMessage = error.localizedDescription
            },
            onChange: { [weak self] snapshot in
                self?.pinned = snapshot.pinned
                self?.history = snapshot.history
                self?.isLoading = false
                self?.errorMessage = nil
            }
        )
    }

    private func performAction(
        _ action: @escaping @Sendable () async throws -> Void
    ) {
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
