import Combine
import Foundation
import GRDB

enum ClipHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case texts = "Texts"
    case images = "Images"
    case files = "Files"
    case folders = "Folders"

    var id: Self { self }
}

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

    func clearHistory() throws {
        let deletedIDs = try repository.deleteAll()
        var deletionError: Error?

        for id in deletedIDs {
            do {
                try blobStorage.deleteAll(for: id)
            } catch {
                deletionError = deletionError ?? error
            }
        }

        if let deletionError {
            throw deletionError
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
    @Published private(set) var isPerformingPaste = false
    @Published private(set) var isRestoring = false
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
    @Published var filter: ClipHistoryFilter = .all {
        didSet {
            guard filter != oldValue, let latestSnapshot else {
                return
            }
            apply(latestSnapshot)
        }
    }

    private let repository: ClipRepository
    private let blobStorage: BlobStorage
    private let actions: ClipHistoryActions
    private let restorer: ClipRestorer
    private let bulkPasteController: BulkPasteController
    private let onRestored: () -> Void
    private let userDefaults: UserDefaults
    private var selectedClips: [Int64: ClipRecord] = [:]
    private var observation: AnyDatabaseCancellable?
    private var pasteTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var selectionRevision = 0
    private var latestSnapshot: ClipHistorySnapshot?

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        restorer: ClipRestorer,
        bulkPasteController: BulkPasteController,
        userDefaults: UserDefaults = .standard,
        onRestored: @escaping () -> Void
    ) {
        self.repository = repository
        self.blobStorage = blobStorage
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
        clip.primaryInteraction == .textSelection && clip.id != nil
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
        selectionRevision &+= 1
    }

    func replaceSelection(with clips: [ClipRecord]) {
        let selectableClips = clips.filter(canBulkSelect)
        selectedClipIDs = selectableClips.compactMap(\.id)
        selectedClips = Dictionary(
            uniqueKeysWithValues: selectableClips.compactMap { clip in
                clip.id.map { ($0, clip) }
            }
        )
        selectionRevision &+= 1
    }

    func clearSelection() {
        guard !selectedClipIDs.isEmpty || !selectedClips.isEmpty else {
            return
        }
        selectedClipIDs.removeAll()
        selectedClips.removeAll()
        selectionRevision &+= 1
    }

    func pasteSelection() {
        let separator = separatorOption.value(customValue: customSeparator)
        startPaste(.separator(separator))
    }

    func pasteSelectionWithSpaces() {
        startPaste(.separator(" "))
    }

    func pasteSelection(format: BulkPasteFormat) {
        startPaste(.format(format))
    }

    func restore(_ clip: ClipRecord) {
        guard restoreTask == nil else {
            return
        }
        isRestoring = true
        restoreTask = Task { [weak self, restorer] in
            guard let self else {
                return
            }
            defer {
                isRestoring = false
                restoreTask = nil
            }
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
            selectionRevision &+= 1
        }
        performAction { [actions] in
            try await actions.delete(clip)
        }
    }

    func clearHistory() {
        clearSelection()
        performAction { [actions] in
            try await actions.clearHistory()
        }
    }

    private enum DefaultsKey {
        static let separatorOption = "bulkPaste.separatorOption"
        static let customSeparator = "bulkPaste.customSeparator"
    }

    private enum PasteRequest {
        case separator(String)
        case format(BulkPasteFormat)
    }

    private func startPaste(_ request: PasteRequest) {
        guard pasteTask == nil else {
            return
        }
        let clips = selectedClipIDs.compactMap { selectedClips[$0] }
        let revision = selectionRevision
        isPerformingPaste = true
        pasteTask = Task { [weak self, bulkPasteController] in
            guard let self else {
                return
            }
            defer {
                isPerformingPaste = false
                pasteTask = nil
            }
            do {
                switch request {
                case .separator(let separator):
                    try await bulkPasteController.paste(clips, separator: separator)
                case .format(let format):
                    try await bulkPasteController.paste(clips, format: format)
                }
                if selectionRevision == revision {
                    clearSelection()
                }
                onRestored()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
                self?.apply(snapshot)
            }
        )
    }

    private func apply(_ snapshot: ClipHistorySnapshot) {
        latestSnapshot = snapshot
        pinned = snapshot.pinned.filter(matchesCurrentFilter)
        history = snapshot.history.filter(matchesCurrentFilter)
        isLoading = false
        errorMessage = nil

        let currentClips = Dictionary(
            uniqueKeysWithValues: (pinned + history).compactMap { clip in
                clip.id.map { ($0, clip) }
            }
        )
        let reconciledIDs = selectedClipIDs.filter { currentClips[$0] != nil }
        if reconciledIDs != selectedClipIDs {
            selectedClipIDs = reconciledIDs
            selectionRevision &+= 1
        }
        selectedClips = Dictionary(
            uniqueKeysWithValues: reconciledIDs.compactMap { id in
                currentClips[id].map { (id, $0) }
            }
        )
    }

    private func matchesCurrentFilter(_ clip: ClipRecord) -> Bool {
        switch filter {
        case .all:
            return true
        case .texts:
            switch ClipContentType(rawValue: clip.type) {
            case .text, .rtf, .url:
                return true
            case .image, .file, nil:
                return false
            }
        case .images:
            return ClipContentType(rawValue: clip.type) == .image
        case .files:
            return ClipContentType(rawValue: clip.type) == .file
                && (try? blobStorage.containsFolder(for: clip)) != true
        case .folders:
            return ClipContentType(rawValue: clip.type) == .file
                && (try? blobStorage.containsFolder(for: clip)) == true
        }
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
