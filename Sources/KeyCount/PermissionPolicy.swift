import Foundation

/// Pure policy shared by both engines and exercised without invoking TCC.
struct MonitoringAuthorization {
    var accessibility: Bool
    var inputMonitoring: Bool
    var canRunFromCurrentLocation = true

    var allowsTextMonitoring: Bool { canRunFromCurrentLocation && accessibility }

    // AppKit's global keyboard monitor also requires Accessibility. Input
    // Monitoring alone must not cause registration to request another service.
    var allowsKeyboardMonitoring: Bool {
        allowsTextMonitoring && inputMonitoring
    }
}

/// Repeated permission probes must not repeatedly register event monitors.
struct MonitoringLifecycle {
    enum Change: Equatable { case none, start, stop }
    private(set) var isRunning = false

    mutating func update(authorized: Bool) -> Change {
        guard authorized != isRunning else { return .none }
        isRunning = authorized
        return authorized ? .start : .stop
    }
}

enum PermissionKind: Hashable {
    case accessibility
    case inputMonitoring
}

/// Main-thread, process-local debounce. A denial is not a reason to prompt
/// again. Subsequent explicit clicks can still open System Settings.
final class PermissionRequestGate {
    private var requested: Set<PermissionKind> = []

    @discardableResult
    func requestIfNeeded(
        _ kind: PermissionKind,
        allowed: Bool,
        isGranted: () -> Bool,
        request: () -> Void
    ) -> Bool {
        guard allowed, !isGranted(), !requested.contains(kind) else { return false }
        // Mark first: request APIs can show an asynchronous or reentrant dialog.
        requested.insert(kind)
        request()
        return true
    }
}

enum AppLaunchLocation: String {
    case applications
    case otherWritableLocation
    case readOnlyVolume

    var allowsPermissionRequests: Bool { self != .readOnlyVolume }

    static func classify(bundleURL: URL, readOnly: Bool, applicationsDirectories: [URL]) -> Self {
        if readOnly { return .readOnlyVolume }
        let app = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let installed = applicationsDirectories.contains { directory in
            let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
            return app.hasPrefix(root + "/")
        }
        return installed ? .applications : .otherWritableLocation
    }
}
