import Foundation

@main
enum PermissionTests {
    static var passed = 0
    static var failed = 0

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
        }
    }

    static func main() {
        let none = MonitoringAuthorization(accessibility: false, inputMonitoring: false)
        let axOnly = MonitoringAuthorization(accessibility: true, inputMonitoring: false)
        let inputOnly = MonitoringAuthorization(accessibility: false, inputMonitoring: true)
        let both = MonitoringAuthorization(accessibility: true, inputMonitoring: true)
        let mounted = MonitoringAuthorization(
            accessibility: true, inputMonitoring: true, canRunFromCurrentLocation: false
        )
        check("no permissions means no text access", !none.allowsTextMonitoring)
        check("no permissions means no event registration", !none.allowsKeyboardMonitoring)
        check("AX alone enables text monitoring", axOnly.allowsTextMonitoring)
        check("AX alone does not enable optional keyboard capture", !axOnly.allowsKeyboardMonitoring)
        check("input access alone does not enable text monitoring", !inputOnly.allowsTextMonitoring)
        check("input access alone must not trigger AppKit's AX request", !inputOnly.allowsKeyboardMonitoring)
        check("both permissions enable keyboard monitoring", both.allowsKeyboardMonitoring)
        check("both permissions enable text monitoring", both.allowsTextMonitoring)
        check("read-only launch never reads another app", !mounted.allowsTextMonitoring)
        check("read-only launch never registers event monitors", !mounted.allowsKeyboardMonitoring)

        var lifecycle = MonitoringLifecycle()
        check("unauthorized startup is a no-op", lifecycle.update(authorized: false) == .none)
        check("grant starts once", lifecycle.update(authorized: true) == .start)
        check("granted is running", lifecycle.isRunning)
        var duplicateStarts = 0
        for _ in 0..<1_000 {
            if lifecycle.update(authorized: true) != .none { duplicateStarts += 1 }
        }
        check("1000 granted probes do not register again", duplicateStarts == 0)
        check("revoke stops once", lifecycle.update(authorized: false) == .stop)
        check("revoked is not running", !lifecycle.isRunning)
        check("repeat revoke is a no-op", lifecycle.update(authorized: false) == .none)
        check("regrant restores monitoring", lifecycle.update(authorized: true) == .start)

        // Model start/stop effects across both services changing independently.
        var keyboard = MonitoringLifecycle()
        var text = MonitoringLifecycle()
        var keyboardStarts = 0, keyboardStops = 0, textStarts = 0, textStops = 0
        for authorization in [none, inputOnly, inputOnly, both, both, axOnly, both, none] {
            switch keyboard.update(authorized: authorization.allowsKeyboardMonitoring) {
            case .start: keyboardStarts += 1
            case .stop: keyboardStops += 1
            case .none: break
            }
            switch text.update(authorized: authorization.allowsTextMonitoring) {
            case .start: textStarts += 1
            case .stop: textStops += 1
            case .none: break
            }
        }
        check("keyboard registrations balanced", keyboardStarts == 2 && keyboardStops == 2)
        check("optional input revocation does not restart text engine", textStarts == 1 && textStops == 1)

        let gate = PermissionRequestGate()
        var requests = 0, probes = 0
        check("read-only launch refuses requests", !gate.requestIfNeeded(
            .accessibility, allowed: false,
            isGranted: { probes += 1; return false }, request: { requests += 1 }
        ))
        check("read-only gate doesn't even probe", probes == 0 && requests == 0)
        check("already granted does not prompt", !gate.requestIfNeeded(
            .accessibility, allowed: true, isGranted: { true }, request: { requests += 1 }
        ))
        check("first explicit AX click requests once", gate.requestIfNeeded(
            .accessibility, allowed: true, isGranted: { false }, request: { requests += 1 }
        ))
        for _ in 0..<1_000 {
            gate.requestIfNeeded(
                .accessibility, allowed: true, isGranted: { false }, request: { requests += 1 }
            )
        }
        check("denial and rapid repeated clicks do not prompt again", requests == 1)
        check("input permission has its own gate", gate.requestIfNeeded(
            .inputMonitoring, allowed: true, isGranted: { false }, request: { requests += 1 }
        ))
        check("only one prompt per permission", requests == 2)
        check("grant then revoke doesn't clear prompt gate", !gate.requestIfNeeded(
            .accessibility, allowed: true, isGranted: { false }, request: { requests += 1 }
        ))

        let reentrant = PermissionRequestGate()
        var nestedRequests = 0
        reentrant.requestIfNeeded(.accessibility, allowed: true, isGranted: { false }) {
            nestedRequests += 1
            reentrant.requestIfNeeded(.accessibility, allowed: true, isGranted: { false }) {
                nestedRequests += 1
            }
        }
        check("request is recorded before asynchronous or reentrant prompt", nestedRequests == 1)

        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Users/test/Applications")
        ]
        func classify(_ path: String, readOnly: Bool = false) -> AppLaunchLocation {
            AppLaunchLocation.classify(
                bundleURL: URL(fileURLWithPath: path), readOnly: readOnly,
                applicationsDirectories: directories
            )
        }
        check("system application directory", classify("/Applications/KeyCount.app") == .applications)
        check("user application directory", classify("/Users/test/Applications/KeyCount.app") == .applications)
        check("downloads copy is not installed", classify("/Users/test/Downloads/KeyCount.app") == .otherWritableLocation)
        check("similarly named directory is not installed", classify("/Applications-old/KeyCount.app") == .otherWritableLocation)
        check("parent components cannot fake installation", classify("/Applications/../Downloads/KeyCount.app") == .otherWritableLocation)
        check("read-only disk image", classify("/Volumes/KeyCount/KeyCount.app", readOnly: true) == .readOnlyVolume)
        check("read-only classification overrides a matching directory", classify("/Applications/KeyCount.app", readOnly: true) == .readOnlyVolume)
        check("development copy may be explicitly authorized", AppLaunchLocation.otherWritableLocation.allowsPermissionRequests)
        check("mounted copy cannot be authorized", !AppLaunchLocation.readOnlyVolume.allowsPermissionRequests)
        print("\nPermissions: \(passed)/\(passed + failed) passed (no TCC calls, prompts, or database changes)")
        exit(failed == 0 ? 0 : 1)
    }
}
