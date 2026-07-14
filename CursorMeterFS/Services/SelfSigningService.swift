import AppKit
import Security

/// Detects the release DMG's ad-hoc code signature (no paid Apple Developer
/// account) at launch and offers a one-time, admin-free fix: create a stable
/// self-signed local certificate and re-sign the installed .app with it, so the
/// Keychain "Always Allow" grant stops silently dropping after relock/sleep/reboot.
///
/// Reuses `scripts/sign-local.sh` (bundled as a resource) instead of duplicating
/// its cert-creation logic — see that file and README "Keychain Prompt Reappears
/// Multiple Times a Day" for the full explanation.
@MainActor
enum SelfSigningService {

    private static let dismissedBuildKey = "SelfSigning.dismissedForBuildVersion"

    /// Call once at launch. No-ops silently unless all of: not an Xcode/dev build,
    /// the running binary is actually ad-hoc signed, and the user hasn't already
    /// said "don't ask again" for this exact build.
    static func checkAndOfferFix() {
        guard !isRunningFromXcode(),
              isAdHocSigned(),
              !dismissedForCurrentBuild(),
              let scriptURL = Bundle.main.url(forResource: "sign-local", withExtension: "sh")
        else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Make Keychain access permanent?"
        alert.informativeText = """
        CursorMeterFS is running with a temporary (ad-hoc) signature, so macOS's \
        Keychain "Always Allow" grant can silently expire — that's why it may ask \
        for your password again every so often.

        Fixing this re-signs the app with a stable, local-only certificate (created \
        in your login Keychain, no admin password) and restarts the app once. This \
        can also be done later by running scripts/sign-local.sh.
        """
        alert.addButton(withTitle: "Fix Now")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Don't Ask Again")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            resignAndRelaunch(scriptPath: scriptURL.path)
        case .alertThirdButtonReturn:
            markDismissed()
        default:
            break // ask again on next launch
        }
    }

    // MARK: - Detection

    /// Skips Xcode/DerivedData builds — Debug is intentionally ad-hoc
    /// (`project.yml`) and its hash changes on every rebuild, so this would just
    /// nag on every ⌘R during active development instead of fixing anything.
    private static func isRunningFromXcode() -> Bool {
        Bundle.main.bundlePath.contains("/Library/Developer/Xcode/DerivedData/")
    }

    private static func isAdHocSigned() -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }

        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return (flags & SecCodeSignatureFlags.adhoc.rawValue) != 0
    }

    // MARK: - Per-build dismissal
    //
    // Every new release is freshly ad-hoc signed (CI signs with `codesign --sign -`
    // each time), so a "don't ask again" choice is scoped to the current build
    // number rather than stored forever — otherwise a user who fixes 1.1.1 would
    // never be offered the fix again after upgrading to a still-unsigned 1.2.0.

    private static func dismissedForCurrentBuild() -> Bool {
        guard let build = currentBuildNumber else { return false }
        return UserDefaults.standard.string(forKey: dismissedBuildKey) == build
    }

    private static func markDismissed() {
        guard let build = currentBuildNumber else { return }
        UserDefaults.standard.set(build, forKey: dismissedBuildKey)
    }

    private static var currentBuildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    // MARK: - Fix

    private static func resignAndRelaunch(scriptPath: String) {
        let appPath = Bundle.main.bundlePath
        let logPath = NSTemporaryDirectory() + "cursormeterfs-selfsign.log"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        // `sleep 1` lets this process fully exit before codesign rewrites the
        // running binary's signature; `open` always runs after, even if signing
        // fails, so the app comes back either way instead of vanishing silently.
        task.arguments = [
            "-c",
            "sleep 1; /bin/bash \"\(scriptPath)\" \"\(appPath)\" >\"\(logPath)\" 2>&1; open \"\(appPath)\"",
        ]
        try? task.run()

        NSApp.terminate(nil)
    }
}
