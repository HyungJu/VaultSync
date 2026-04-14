import Foundation

enum L10n {
    private static var isKorean: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ko") == true
    }

    static var appTitle: String { isKorean ? "VaultSync" : "VaultSync" }
    static var appSubtitle: String { isKorean ? "로컬 볼트의 변경사항을 원격 저장소에 업데이트 합니다." : "Push local vault changes to your remote repository." }
    static var vaults: String { isKorean ? "내 볼트" : "Your Vaults" }
    static var addVault: String { isKorean ? "볼트 추가" : "Add Vault" }
    static var remove: String { isKorean ? "삭제" : "Remove" }
    static var openWindow: String { isKorean ? "창 열기" : "Open Window" }
    static var openSetup: String { isKorean ? "설정" : "Setup" }
    static var details: String { isKorean ? "설정 상세" : "Details" }
    static var activity: String { isKorean ? "활동 로그" : "Activity" }
    static var pushNow: String { isKorean ? "지금 푸시" : "Push Now" }
    static var startWatching: String { isKorean ? "감시 시작" : "Start Watching" }
    static var stopWatching: String { isKorean ? "감시 중지" : "Pause Watching" }
    static var clearLog: String { isKorean ? "로그 지우기" : "Clear Log" }
    static var repository: String { isKorean ? "저장소" : "Repository" }
    static var vaultFolder: String { isKorean ? "볼트 폴더" : "Vault folder" }
    static var branch: String { isKorean ? "브랜치" : "Branch" }
    static var remoteName: String { isKorean ? "리모트 이름" : "Remote name" }
    static var delay: String { isKorean ? "변경 후 대기 시간" : "Delay after a change" }
    static func setupWindowTitle(_ name: String) -> String { isKorean ? "\(name) 설정" : "Set up \(name)" }
    static var step1: String { isKorean ? "1단계. 푸시할 원격 저장소를 연결하세요." : "Step 1. Connect the remote repository you want to push to." }
    static var step2: String { isKorean ? "2단계. iCloud Drive 안의 볼트 폴더를 선택하세요." : "Step 2. Choose the vault folder, including one inside iCloud Drive." }
    static var step3: String { isKorean ? "3단계. 원격 저장소를 덮어써도 되는지 확인하세요." : "Step 3. Confirm whether GitSync may overwrite the remote repository." }
    static var finishSetup: String { isKorean ? "설정 완료" : "Finish Setup" }
    static var next: String { isKorean ? "다음" : "Next" }
    static var back: String { isKorean ? "이전" : "Back" }
    static var chooseFolder: String { isKorean ? "폴더 선택" : "Choose Folder" }
    static var showInFinder: String { isKorean ? "Finder에서 보기" : "Show in Finder" }
    static var overwriteTitle: String { isKorean ? "원격 저장소 덮어쓰기 허용" : "Allow remote overwrite" }
    static var overwriteDescription: String { isKorean ? "원격 저장소에 이미 파일이 있으면 로컬 볼트 기준으로 덮어쓸 수 있습니다." : "If the remote repository already has files, GitSync may overwrite them with your local vault." }
    static var overwriteWarning: String { isKorean ? "원격 저장소에 기존 내용이 있다면 사라질 수 있습니다." : "Existing files in the remote repository may be replaced." }
    static var simpleDelayDescription: String { isKorean ? "폴더 변경을 감지한 뒤 잠시 기다렸다가 한 번에 푸시합니다." : "GitSync waits briefly after file changes, then pushes them in one batch." }
    static var addNewFiles: String { isKorean ? "새 파일 자동 포함" : "Include new files automatically" }
    static var autoStart: String { isKorean ? "앱 시작 시 자동 감시" : "Start watching automatically" }
    static var nothingYet: String { isKorean ? "아직 표시할 내용이 없습니다." : "Nothing to show yet." }
    static var notConnectedYet: String { isKorean ? "아직 연결되지 않음" : "Not connected yet" }
    static func secondsAfterChange(_ seconds: String) -> String { isKorean ? "변경 후 \(seconds)초 뒤 푸시" : "Push \(seconds) seconds after changes" }
    static var usingBundled: String { isKorean ? "앱에 포함된 git-sync 사용 중" : "Using the built-in git-sync shipped with the app." }
}
