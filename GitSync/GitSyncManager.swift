import AppKit
import Combine
import CoreServices
import Foundation
import SwiftUI
import UserNotifications

struct CommandResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum SyncFailure: LocalizedError {
    case missingBinary(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingBinary(path):
            return "Bundled git-sync could not be found at \(path)."
        case let .commandFailed(message):
            return message
        }
    }
}

final class ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: String? = nil
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }

            if executable.contains("/") {
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [executable] + arguments
            }

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: CommandResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(decoding: stdoutData, as: UTF8.self),
                    standardError: String(decoding: stderrData, as: UTF8.self)
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

final class FSEventWatcher {
    private var streamRef: FSEventStreamRef?
    private let callback: @MainActor () -> Void

    init(callback: @escaping @MainActor () -> Void) {
        self.callback = callback
    }

    func start(path: String) {
        stop()

        let pathsToWatch = [path] as CFArray
        let callbackPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var context = FSEventStreamContext(
            version: 0,
            info: callbackPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FSEventWatcher>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    watcher.callback()
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        self.streamRef = nil
    }

    deinit {
        stop()
    }
}

@MainActor
final class SyncTargetViewModel: NSObject, ObservableObject, Identifiable {
    @Published var target: SyncTarget {
        didSet { onChange() }
    }
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isSyncingNow = false
    @Published private(set) var isPreparing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastErrorMessage: String?

    private let onChange: () -> Void
    private let logLimit = 250
    private let minimumSyncIndicatorDuration: TimeInterval = 0.8
    private var lastFailureFingerprint: String?
    private var watcher: FSEventWatcher?
    private var scheduledSyncTask: Task<Void, Never>?

    init(target: SyncTarget, onChange: @escaping () -> Void) {
        self.target = target
        self.onChange = onChange
        super.init()
    }

    var id: UUID { target.id }

    var managedRepositoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("VaultSync", isDirectory: true)
            .appendingPathComponent("Repos", isDirectory: true)
            .appendingPathComponent("\(target.id.uuidString).git", isDirectory: true)
    }

    private var vaultURL: URL {
        URL(fileURLWithPath: target.vaultDirectory)
    }

    var menuIconName: String {
        if isPreparing || isSyncingNow {
            return "arrow.up.circle.fill"
        }
        if lastErrorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        return isRunning ? "checkmark.circle.fill" : "pause.circle.fill"
    }

    var statusLine: String {
        if isPreparing {
            return "Preparing your vault"
        }
        if let message = lastErrorMessage {
            return "Needs attention: \(message)"
        }
        if isSyncingNow {
            return "Syncing changes"
        }
        if isRunning {
            if let lastSyncDate {
                return "Watching, last sync \(lastSyncDate.formatted(date: .omitted, time: .shortened))"
            }
            return "Watching for changes"
        }
        return "Not watching"
    }

    func binding<Value>(
        for keyPath: WritableKeyPath<SyncTarget, Value>,
        transform: ((inout SyncTarget) -> Void)? = nil
    ) -> Binding<Value> {
        Binding(
            get: { self.target[keyPath: keyPath] },
            set: { newValue in
                self.target[keyPath: keyPath] = newValue
                transform?(&self.target)
            }
        )
    }

    func start() {
        guard target.isReadyToRun else {
            fail("Finish setup first.")
            return
        }
        guard !isRunning else { return }

        lastErrorMessage = nil
        isRunning = true
        addLog("Watching \(target.name)")
        startWatching()
        scheduleSync(reason: "Startup sync")
    }

    func stop() {
        scheduledSyncTask?.cancel()
        scheduledSyncTask = nil
        watcher?.stop()
        watcher = nil
        isRunning = false
        isSyncingNow = false
        addLog("Stopped watching")
    }

    func syncNow() {
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { [weak self] in
            await self?.performSyncCycle(trigger: "Manual sync")
        }
    }

    func clearLogs() {
        logs.removeAll()
        addLog("Logs cleared")
    }

    func prepareInitialPush() async {
        isPreparing = true
        lastErrorMessage = nil
        addLog("Preparing \(target.name)")

        do {
            stop()
            let backupURL = try backupVaultContents()
            try await recreateBaseRepository()
            try await ensureRemoteConfiguredInBaseRepo()
            try await createEmptyWorktree()
            try restoreBackupContents(from: backupURL)
            try await snapshotLocalFilesIfNeeded()
            try await ensureLocalBranchExistsForUpload()
            try await ensureTrackingConfig()
            try await pushLocalBranch(setUpstream: true)

            isPreparing = false
            addLog("Setup completed")

            if target.startAtLaunch || isRunning {
                start()
            }
        } catch {
            isPreparing = false
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fail(message)
        }
    }

    private func startWatching() {
        let path = target.vaultDirectory
        let watcher = FSEventWatcher { [weak self] in
            self?.scheduleSync(reason: "Change detected")
        }
        watcher.start(path: path)
        self.watcher = watcher
    }

    private func scheduleSync(reason: String) {
        guard isRunning else { return }
        scheduledSyncTask?.cancel()

        scheduledSyncTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(self.target.sanitizedSettleDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await self.performSyncCycle(trigger: reason)
        }
    }

    private func performSyncCycle(trigger: String) async {
        guard !isSyncingNow else { return }

        let syncStartedAt = Date()
        isSyncingNow = true
        addLog("\(trigger)")

        do {
            try await ensureWorktreeReady()
            try await ensureTrackingConfig()
            try await snapshotLocalFilesIfNeeded()
            try await ensureLocalBranchExistsForUpload()
            try await pushLocalBranch(setUpstream: false)

            lastSyncDate = Date()
            lastErrorMessage = nil
            lastFailureFingerprint = nil
            addLog("Sync complete")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fail(message)
        }

        let elapsed = Date().timeIntervalSince(syncStartedAt)
        if elapsed < minimumSyncIndicatorDuration {
            let remaining = minimumSyncIndicatorDuration - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        isSyncingNow = false
    }

    private func snapshotLocalFilesIfNeeded() async throws {
        _ = try await runWorktreeGit(["add", "-A"])
        let diffResult = try await runWorktreeGitAllowingFailure(["diff", "--cached", "--quiet"])
        let hasHead = try await worktreeGitSucceeds(["rev-parse", "--verify", "HEAD"])

        if diffResult.exitCode == 0 && hasHead {
            addLog("No local changes to save")
            return
        }

        if diffResult.exitCode == 0 && !hasHead {
            addLog("No local files found yet")
            return
        }

        _ = try await runWorktreeGit(["commit", "-m", commitMessage])
        addLog("Saved the current vault locally")
    }

    private func ensureLocalBranchExistsForUpload() async throws {
        let hasHead = try await worktreeGitSucceeds(["rev-parse", "--verify", "HEAD"])
        guard !hasHead else { return }
        _ = try await runWorktreeGit(["commit", "--allow-empty", "-m", initialCommitMessage])
        addLog("Created an initial empty vault commit")
    }

    private var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private var timestampString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: Date())
    }

    private var commitMessage: String {
        "Vault update from \(deviceName) at \(timestampString)"
    }

    private var initialCommitMessage: String {
        "Initial vault from \(deviceName) at \(timestampString)"
    }

    private func ensureTrackingConfig() async throws {
        _ = try await runWorktreeGit(["config", "branch.\(target.branchName).remote", target.remoteName])
        _ = try await runWorktreeGit(["config", "branch.\(target.branchName).merge", "refs/heads/\(target.branchName)"])
    }

    private func pushLocalBranch(setUpstream: Bool) async throws {
        var arguments = ["push"]
        if setUpstream {
            arguments.append("-u")
        }
        if target.overwriteRemote {
            arguments.append("--force")
        }
        arguments.append(target.remoteName)
        arguments.append("\(target.branchName):\(target.branchName)")
        _ = try await runWorktreeGit(arguments)
    }

    private func worktreeGitSucceeds(_ arguments: [String]) async throws -> Bool {
        let result = try await runWorktreeGitAllowingFailure(arguments)
        return result.exitCode == 0
    }

    private func runBaseGit(_ arguments: [String]) async throws -> CommandResult {
        let result = try await runBaseGitAllowingFailure(arguments)
        if result.exitCode != 0 {
            throw SyncFailure.commandFailed(renderFailure("git \(arguments.joined(separator: " "))", result: result))
        }
        addCommandOutput(result)
        return result
    }

    private func runBaseGitAllowingFailure(_ arguments: [String]) async throws -> CommandResult {
        try await runCommand(
            executable: "/usr/bin/git",
            arguments: ["--git-dir=\(managedRepositoryURL.path)"] + arguments,
            environment: [:],
            allowFailure: true,
            currentDirectory: managedRepositoryURL.deletingLastPathComponent().path
        )
    }

    private func runWorktreeGit(_ arguments: [String]) async throws -> CommandResult {
        let result = try await runWorktreeGitAllowingFailure(arguments)
        if result.exitCode != 0 {
            throw SyncFailure.commandFailed(renderFailure("git \(arguments.joined(separator: " "))", result: result))
        }
        addCommandOutput(result)
        return result
    }

    private func runWorktreeGitAllowingFailure(_ arguments: [String]) async throws -> CommandResult {
        try await runCommand(
            executable: "/usr/bin/git",
            arguments: arguments,
            environment: [:],
            allowFailure: true,
            currentDirectory: target.vaultDirectory
        )
    }

    private func ensureBaseRepoParentExists() throws {
        try FileManager.default.createDirectory(
            at: managedRepositoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func recreateBaseRepository() async throws {
        try ensureBaseRepoParentExists()
        if FileManager.default.fileExists(atPath: managedRepositoryURL.path) {
            try FileManager.default.removeItem(at: managedRepositoryURL)
        }
        addLog("Creating hidden base repository")
        _ = try await runCommand(
            executable: "/usr/bin/git",
            arguments: ["init", "--bare", "--initial-branch=\(target.branchName)", managedRepositoryURL.path],
            environment: [:],
            allowFailure: false
        )
    }

    private func ensureRemoteConfiguredInBaseRepo() async throws {
        if try await baseGitSucceeds(["remote", "get-url", target.remoteName]) {
            _ = try await runBaseGit(["remote", "set-url", target.remoteName, target.trimmedRemoteURL])
        } else if !target.trimmedRemoteURL.isEmpty {
            _ = try await runBaseGit(["remote", "add", target.remoteName, target.trimmedRemoteURL])
        }
    }

    private func baseGitSucceeds(_ arguments: [String]) async throws -> Bool {
        let result = try await runBaseGitAllowingFailure(arguments)
        return result.exitCode == 0
    }

    private func backupVaultContents() throws -> URL? {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return nil }
        let backupURL = FileManager.default.temporaryDirectory.appendingPathComponent("VaultSyncBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let children = try FileManager.default.contentsOfDirectory(at: vaultURL, includingPropertiesForKeys: nil)
        for child in children where child.lastPathComponent != ".git" {
            try FileManager.default.copyItem(at: child, to: backupURL.appendingPathComponent(child.lastPathComponent))
        }
        return backupURL
    }

    private func restoreBackupContents(from backupURL: URL?) throws {
        guard let backupURL else { return }
        let children = try FileManager.default.contentsOfDirectory(at: backupURL, includingPropertiesForKeys: nil)
        for child in children {
            let destination = vaultURL.appendingPathComponent(child.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: child, to: destination)
        }
        try? FileManager.default.removeItem(at: backupURL)
    }

    private func removeVaultDirectoryIfPresent() throws {
        if FileManager.default.fileExists(atPath: vaultURL.path) {
            try FileManager.default.removeItem(at: vaultURL)
        }
    }

    private func createWorktreeUsingRemoteContents() async throws {
        try removeVaultDirectoryIfPresent()
        _ = try await runBaseGit(["fetch", target.remoteName, target.branchName])
        let hasRemoteBranch = try await baseGitSucceeds(["rev-parse", "--verify", "\(target.remoteName)/\(target.branchName)"])
        guard hasRemoteBranch else {
            throw SyncFailure.commandFailed("The remote branch \(target.branchName) could not be found.")
        }
        _ = try await runBaseGit(["worktree", "add", "--checkout", "-B", target.branchName, target.vaultDirectory, "\(target.remoteName)/\(target.branchName)"])
        try await ensureTrackingConfig()
        addLog("Created a linked worktree in the vault folder")
    }

    private func createEmptyWorktree() async throws {
        try removeVaultDirectoryIfPresent()
        _ = try await runBaseGit(["worktree", "add", "--checkout", "--orphan", "-b", target.branchName, target.vaultDirectory])
        try await ensureTrackingConfig()
        addLog("Created a linked worktree in the vault folder")
    }

    private func ensureWorktreeReady() async throws {
        let baseExists = FileManager.default.fileExists(atPath: managedRepositoryURL.path)
        let vaultExists = FileManager.default.fileExists(atPath: vaultURL.path)
        guard baseExists, vaultExists else {
            throw SyncFailure.commandFailed("This vault has not finished setup yet. Open the setup guide again.")
        }
        let result = try await runWorktreeGitAllowingFailure(["rev-parse", "--is-inside-work-tree"])
        guard result.exitCode == 0, result.standardOutput.contains("true") else {
            throw SyncFailure.commandFailed("The selected folder is not linked as a git worktree yet. Open the setup guide again.")
        }
    }

    private func runCommand(
        executable: String,
        arguments: [String],
        environment: [String: String],
        allowFailure: Bool,
        currentDirectory: String? = nil
    ) async throws -> CommandResult {
        do {
            let result = try await ProcessRunner.run(
                executable: executable,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory
            )
            if !allowFailure && result.exitCode != 0 {
                throw SyncFailure.commandFailed(renderFailure(executable, result: result))
            }
            return result
        } catch {
            if let syncFailure = error as? SyncFailure {
                throw syncFailure
            }
            throw SyncFailure.commandFailed(error.localizedDescription)
        }
    }

    private func renderFailure(_ command: String, result: CommandResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = !stderr.isEmpty ? stderr : stdout
        return details.isEmpty ? "\(command) failed with exit code \(result.exitCode)" : details
    }

    private func addCommandOutput(_ result: CommandResult) {
        let output = [result.standardOutput, result.standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in output.joined(separator: "\n").split(separator: "\n") {
            addLog(String(line))
        }
    }

    private func fail(_ message: String) {
        lastErrorMessage = message
        addLog(message, isError: true)

        if lastFailureFingerprint != message {
            sendNotification(title: "VaultSync needs attention", body: "\(target.name): \(message)")
            lastFailureFingerprint = message
        }
    }

    private func addLog(_ message: String, isError: Bool = false) {
        logs.append(LogEntry(timestamp: Date(), message: message, isError: isError))
        if logs.count > logLimit {
            logs.removeFirst(logs.count - logLimit)
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

@MainActor
final class GitSyncManager: NSObject, ObservableObject {
    static let shared = GitSyncManager()

    @Published private(set) var targets: [SyncTargetViewModel] = []
    @Published var selectedTargetID: UUID? {
        didSet { persistStore() }
    }
    @Published var setupTargetID: UUID?

    private let storageKey = "syncTargetsStore"
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        requestNotificationAuthorization()
        loadStore()

        if targets.isEmpty {
            let target = addTarget(named: "My Vault", shouldOpenSetup: true)
            selectedTargetID = target.id
        }

        for target in targets where target.target.startAtLaunch && target.target.isReadyToRun {
            target.start()
        }
    }

    var selectedTarget: SyncTargetViewModel? {
        guard let selectedTargetID else { return targets.first }
        return targets.first(where: { $0.id == selectedTargetID }) ?? targets.first
    }

    var menuBarIconName: String {
        if targets.contains(where: { $0.isPreparing || $0.isSyncingNow }) {
            return "arrow.trianglehead.2.clockwise.circle.fill"
        }
        if targets.contains(where: { $0.lastErrorMessage != nil }) {
            return "exclamationmark.triangle.fill"
        }
        if targets.contains(where: { $0.isRunning }) {
            return "checkmark.circle.fill"
        }
        return "pause.circle.fill"
    }

    @discardableResult
    func addTarget(named name: String = "New Vault", shouldOpenSetup: Bool = true) -> SyncTargetViewModel {
        let target = SyncTarget(name: name)
        let viewModel = makeTargetViewModel(target)
        targets.append(viewModel)
        observeTarget(viewModel)
        selectedTargetID = viewModel.id
        if shouldOpenSetup {
            setupTargetID = viewModel.id
        }
        persistStore()
        return viewModel
    }

    func removeSelectedTarget() {
        guard let selectedTarget else { return }
        selectedTarget.stop()
        targets.removeAll { $0.id == selectedTarget.id }
        selectedTargetID = targets.first?.id
        persistStore()
    }

    func selectTarget(_ id: UUID) {
        selectedTargetID = id
    }

    func openSetup(for id: UUID? = nil) {
        setupTargetID = id ?? selectedTargetID
    }

    func closeSetup() {
        setupTargetID = nil
    }

    func setupTargetViewModel() -> SyncTargetViewModel? {
        guard let setupTargetID else { return nil }
        return targets.first(where: { $0.id == setupTargetID })
    }

    func revealPath(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func chooseVaultDirectory(for target: SyncTargetViewModel? = nil) {
        chooseDirectory(title: "Choose your vault folder") { url in
            (target ?? self.selectedTarget)?.target.vaultDirectory = url.path
        }
    }

    func chooseGitSyncBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose a custom git-sync binary"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedTarget?.target.gitSyncBinary = url.path
        }
    }

    private func requestNotificationAuthorization() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func loadStore() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(PersistedTargets.self, from: data)
        else { return }

        targets = decoded.targets.map(makeTargetViewModel)
        selectedTargetID = decoded.selectedTargetID ?? decoded.targets.first?.id
        targets.forEach(observeTarget)
    }

    private func makeTargetViewModel(_ target: SyncTarget) -> SyncTargetViewModel {
        SyncTargetViewModel(target: target) { [weak self] in
            self?.persistStore()
        }
    }

    private func observeTarget(_ target: SyncTargetViewModel) {
        target.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func persistStore() {
        let store = PersistedTargets(
            targets: targets.map(\.target),
            selectedTargetID: selectedTargetID ?? targets.first?.id
        )
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func chooseDirectory(title: String, handler: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            handler(url)
        }
    }
}
