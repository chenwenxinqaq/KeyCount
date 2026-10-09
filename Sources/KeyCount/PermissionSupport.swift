import AppKit
import ApplicationServices
import Security

enum AppInstallation {
    static let current: AppLaunchLocation = {
        let bundle = Bundle.main.bundleURL
        // A public volume property, not a guess based on private translocation
        // directory names. A read-only copy must be moved before requesting access.
        let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?
            .volumeIsReadOnly ?? false
        let directories = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        return AppLaunchLocation.classify(
            bundleURL: bundle, readOnly: readOnly, applicationsDirectories: directories
        )
    }()

    static func authorization() -> MonitoringAuthorization {
        MonitoringAuthorization(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            canRunFromCurrentLocation: current.allowsPermissionRequests
        )
    }
}

enum AppActions {
    private static let requests = PermissionRequestGate()

    static func openAccessibilitySettings() {
        guard AppInstallation.current.allowsPermissionRequests else {
            openApplicationsFolder()
            return
        }
        requests.requestIfNeeded(
            .accessibility, allowed: true, isGranted: { AXIsProcessTrusted() }
        ) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        openSettings("Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        guard AppInstallation.current.allowsPermissionRequests else {
            openApplicationsFolder()
            return
        }
        requests.requestIfNeeded(
            .inputMonitoring, allowed: true, isGranted: { CGPreflightListenEventAccess() }
        ) {
            _ = CGRequestListenEventAccess()
        }
        openSettings("Privacy_ListenEvent")
    }

    static func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    private static func openSettings(_ page: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(page)") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum PermissionDiagnostics {
    /// On-demand metadata only: no focused apps, text contents, or TCC database.
    static func report() -> String {
        let bundle = Bundle.main
        let access = AppInstallation.authorization()
        return """
        KeyCount permission diagnostics
        Version: \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
        Build: \(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Bundle ID: \(bundle.bundleIdentifier ?? "-")
        Running app: \(bundle.bundleURL.path)
        Launch location: \(AppInstallation.current.rawValue)
        AX trusted: \(access.accessibility)
        Listen access: \(access.inputMonitoring)
        Monitoring allowed here: \(access.canRunFromCurrentLocation)
        Signature: \(signatureDescription())
        """
    }

    private static func signatureDescription() -> String {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return "unavailable"
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            return "unavailable"
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return "unsigned or unavailable"
        }
        let status = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if SecCodeSignatureFlags(rawValue: status).contains(.adhoc) {
            return "ad-hoc (local test build; not a persistent publisher identity)"
        }
        return "signed; team=\(info[kSecCodeInfoTeamIdentifier as String] as? String ?? "none")"
    }
}
