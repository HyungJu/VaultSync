import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var manager: GitSyncManager
    @ObservedObject var target: SyncTargetViewModel

    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.setupWindowTitle(target.target.name))
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(stepSubtitle)
                .foregroundStyle(.secondary)

            Group {
                switch step {
                case 0:
                    repositoryStep
                case 1:
                    folderStep
                default:
                    confirmationStep
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))

            HStack {
                if step > 0 {
                    Button(L10n.back) {
                        step -= 1
                    }
                }

                Spacer()

                if step < 2 {
                    Button(L10n.next) {
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(target.isPreparing ? "..." : L10n.finishSetup) {
                        Task {
                            await target.prepareInitialPush()
                            manager.closeSetup()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(target.isPreparing)
                }
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    private var stepSubtitle: String {
        switch step {
        case 0:
            return L10n.step1
        case 1:
            return L10n.step2
        default:
            return L10n.step3
        }
    }

    private var repositoryStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Vault", text: target.binding(for: \.name))
            field(L10n.repository, text: target.binding(for: \.remoteURL))

            HStack {
                field(L10n.branch, text: target.binding(for: \.branchName))
                field(L10n.remoteName, text: target.binding(for: \.remoteName))
            }
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(L10n.vaultFolder, text: target.binding(for: \.vaultDirectory))
            HStack {
                Button(L10n.chooseFolder) {
                    manager.chooseVaultDirectory(for: target)
                }
                Button(L10n.showInFinder) {
                    manager.revealPath(target.target.vaultDirectory)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.simpleDelayDescription)
                    .foregroundStyle(.secondary)
                TextField(
                    "3",
                    value: target.binding(for: \.settleDelay, transform: { $0.settleDelay = max($0.settleDelay, 0.5) }),
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            }
        }
    }

    private var confirmationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(L10n.overwriteTitle, isOn: target.binding(for: \.overwriteRemote))
            Text(L10n.overwriteDescription)
                .foregroundStyle(.secondary)
            Text(L10n.overwriteWarning)
                .foregroundStyle(.orange)
                .font(.caption)
            Toggle(L10n.autoStart, isOn: target.binding(for: \.startAtLaunch))
            Toggle(L10n.addNewFiles, isOn: target.binding(for: \.syncNewFiles))
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
