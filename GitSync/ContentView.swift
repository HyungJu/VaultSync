import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: GitSyncManager
    let compact: Bool
    var onOpenWindow: (() -> Void)? = nil
    var onOpenSetup: ((UUID?) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                targetListCard

                if let target = manager.selectedTarget {
                    overviewCard(target)
                    actionsCard(target)

                    if !compact {
                        detailsCard(target)
                    }

                    logsCard(target)
                }
            }
            .padding(18)
        }
        .frame(minWidth: compact ? 420 : 880, idealWidth: compact ? 460 : 920, minHeight: compact ? 560 : 760)
        .background(background)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.97, blue: 1.0),
                Color(red: 0.91, green: 0.95, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.appTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(L10n.appSubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var targetListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.vaults)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(L10n.addVault) {
                    let target = manager.addTarget()
                    onOpenSetup?(target.id)
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.remove) {
                    manager.removeSelectedTarget()
                }
                .disabled(manager.selectedTarget == nil)
            }

            ForEach(manager.targets) { target in
                Button {
                    manager.selectTarget(target.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: target.menuIconName)
                            .foregroundStyle(.primary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.target.name)
                                .font(.headline)
                            Text(target.statusLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if manager.selectedTargetID == target.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(manager.selectedTargetID == target.id ? Color.white.opacity(0.65) : Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private func overviewCard(_ target: SyncTargetViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(target.statusLine, systemImage: target.menuIconName)
                    .font(.headline)
                Spacer()
                Button(L10n.openSetup) {
                    onOpenSetup?(target.id)
                }
            }

            overviewRow(L10n.repository, value: target.target.remoteURL.isEmpty ? L10n.notConnectedYet : target.target.remoteURL)
            overviewRow(L10n.vaultFolder, value: target.target.vaultDirectory)
            overviewRow(L10n.branch, value: target.target.branchName)
            overviewRow(L10n.delay, value: L10n.secondsAfterChange(target.target.sanitizedSettleDelay.formatted()))
            if target.target.overwriteRemote {
                Text(L10n.overwriteWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .cardStyle()
    }

    private func actionsCard(_ target: SyncTargetViewModel) -> some View {
        HStack {
            Button(target.isRunning ? L10n.stopWatching : L10n.startWatching) {
                target.isRunning ? target.stop() : target.start()
            }
            .buttonStyle(.borderedProminent)

            Button(L10n.pushNow) {
                target.syncNow()
            }
            .disabled(target.isPreparing || target.isSyncingNow)

            Button(L10n.clearLog) {
                target.clearLogs()
            }

            Spacer()

            if compact {
                Button(L10n.openWindow) {
                    onOpenWindow?()
                }
            }
        }
        .cardStyle()
    }

    private func detailsCard(_ target: SyncTargetViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.details)
                .font(.title3.weight(.semibold))

            textFieldRow("Vault", text: target.binding(for: \.name))
            textFieldRow(L10n.repository, text: target.binding(for: \.remoteURL))

            HStack {
                textFieldRow(L10n.branch, text: target.binding(for: \.branchName))
                textFieldRow(L10n.remoteName, text: target.binding(for: \.remoteName))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.vaultFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField(L10n.vaultFolder, text: target.binding(for: \.vaultDirectory))
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.chooseFolder) {
                        manager.chooseVaultDirectory(for: target)
                    }
                    Button(L10n.showInFinder) {
                        manager.revealPath(target.target.vaultDirectory)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.delay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "3",
                    value: target.binding(for: \.settleDelay, transform: { $0.settleDelay = max($0.settleDelay, 0.5) }),
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
            }

            HStack {
                Toggle(L10n.addNewFiles, isOn: target.binding(for: \.syncNewFiles))
                Toggle(L10n.autoStart, isOn: target.binding(for: \.startAtLaunch))
                Toggle(L10n.overwriteTitle, isOn: target.binding(for: \.overwriteRemote))
            }
            Text(L10n.overwriteDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func logsCard(_ target: SyncTargetViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.activity)
                .font(.title3.weight(.semibold))

            if target.logs.isEmpty {
                Text(L10n.nothingYet)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(target.logs.reversed()) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .frame(width: 92, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .foregroundStyle(entry.isError ? .red : .primary)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(minHeight: compact ? 220 : 300)
            }
        }
        .cardStyle()
    }

    private func overviewRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func textFieldRow(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
    }
}
