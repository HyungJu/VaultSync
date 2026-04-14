import Foundation

struct SyncTarget: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "My Vault"
    var vaultDirectory: String = ""
    var remoteName: String = "origin"
    var remoteURL: String = ""
    var branchName: String = "main"
    var settleDelay: Double = 3
    var gitSyncBinary: String = ""
    var syncNewFiles: Bool = true
    var syncForceEnable: Bool = true
    var overwriteRemote: Bool = false
    var startAtLaunch: Bool = true

    var trimmedRemoteURL: String {
        remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedSettleDelay: Double {
        max(settleDelay, 0.5)
    }

    var isReadyToRun: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !vaultDirectory.isEmpty &&
        !branchName.isEmpty
    }
}

struct PersistedTargets: Codable {
    var targets: [SyncTarget]
    var selectedTargetID: UUID?
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool
}
