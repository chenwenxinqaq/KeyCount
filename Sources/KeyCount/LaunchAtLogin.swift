import ServiceManagement

/// 开机自启开关，基于 macOS 13+ 的 SMAppService。
/// 注意：仅在以 .app bundle 形式运行、且已签名时有效。
enum LaunchAtLogin {

    /// 当前是否已注册开机自启
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Set the requested value, rather than toggling again when the UI rolls back.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled else { return }
            try SMAppService.mainApp.register()
        } else if isEnabled || requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
