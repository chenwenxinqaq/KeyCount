import AppKit
import SwiftUI

struct SettingsView: View {
    let snapshot: DashboardSnapshot
    @ObservedObject var preferences: AppPreferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginMessage: String?
    @State private var folderError: String?
    @State private var diagnosticMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("主要指标", symbol: "chart.bar")
                    Picker("主要指标", selection: $preferences.primaryMetric) {
                        ForEach(PrimaryMetric.allCases) { option in
                            Text(option.shortTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    Text(preferences.primaryMetric.explanation)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(preferences.primaryMetric.needsInputMonitoring
                        ? "菜单栏、趋势图和每日目标都按敲键字符计算；另两项仍在面板里显示。"
                        : "菜单栏、趋势图和每日目标都按\(preferences.primaryMetric.shortTitle)计算；另两项仍在面板里显示。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("每日目标", symbol: "scope")
                    preferenceToggle("显示每日目标", isOn: $preferences.goalEnabled)
                    if preferences.goalEnabled {
                        HStack {
                            Text("目标数量").foregroundStyle(.secondary)
                            Spacer()
                            Stepper(
                                value: $preferences.dailyGoal,
                                in: AppPreferences.goalRange,
                                step: 100
                            ) {
                                Text("\(preferences.dailyGoal.formatted()) \(preferences.primaryMetric.unit)")
                                    .monospacedDigit()
                                    .frame(minWidth: 78, alignment: .trailing)
                            }
                            .fixedSize()
                            .accessibilityLabel("每日目标")
                        }
                        HStack(spacing: 6) {
                            ForEach([1_000, 2_000, 5_000, 10_000], id: \.self) { goal in
                                Button {
                                    preferences.dailyGoal = goal
                                } label: {
                                    Text(goal.formatted())
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(
                                            preferences.dailyGoal == goal ? Theme.accent.opacity(0.12) : Theme.muted,
                                            in: RoundedRectangle(cornerRadius: 7)
                                        )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(preferences.dailyGoal == goal ? Theme.accent : Color.secondary)
                                .accessibilityLabel("设置每日目标 \(goal) 字")
                            }
                        }
                    }
                }
            }

            PanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("使用习惯", symbol: "switch.2")
                    preferenceToggle("菜单栏显示数值", isOn: $preferences.showMenuBarCount)
                    preferenceToggle("登录时自动启动", isOn: Binding(
                        get: { launchAtLogin },
                        set: { setLaunchAtLogin($0) }
                    ))
                    if let loginMessage {
                        Text(loginMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            PanelCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("悬浮窗", symbol: "macwindow.on.rectangle")
                    preferenceToggle("显示置顶悬浮窗", isOn: $preferences.showOverlay)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if preferences.showOverlay {
                        HStack(spacing: 10) {
                            Text("不透明度").foregroundStyle(.secondary)
                            Slider(value: $preferences.overlayOpacity,
                                   in: AppPreferences.opacityRange)
                            Text("\(Int((preferences.overlayOpacity * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(minWidth: 34, alignment: .trailing)
                        }
                        .controlSize(.small)
                        preferenceToggle("鼠标穿透（点击落到下方窗口）",
                                         isOn: $preferences.overlayClickThrough)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Text(preferences.overlayClickThrough
                            ? "悬浮窗半透明置顶显示当前主要指标；鼠标穿透开启时无法拖动，关闭后可拖动窗体任意处移动。"
                            : "悬浮窗半透明置顶显示当前主要指标；拖动窗体任意处即可移动，位置会被记住。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            PanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("权限与隐私", symbol: "lock.shield")
                    permissionRow(
                        "辅助功能",
                        subtitle: "计算上屏与净字数 · "
                            + (preferences.primaryMetric.needsInputMonitoring ? "可选" : "必需"),
                        granted: snapshot.hasAccessibility,
                        action: AppActions.openAccessibilitySettings
                    )
                    Divider()
                    permissionRow(
                        "输入监控",
                        subtitle: "统计敲键字符与活动分布 · "
                            + (preferences.primaryMetric.needsInputMonitoring ? "必需" : "可选"),
                        granted: snapshot.hasInputMonitoring,
                        action: AppActions.openInputMonitoringSettings
                    )
                    Text("原文仅在内存中用于计算差值；磁盘只保存每日汇总，不上传。部分应用不提供可读取的文本，可能无法统计。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.launchLocation == .readOnlyVolume
                        ? "当前副本位于只读位置，已暂停监控及授权请求。请先安装到“应用程序”。"
                        : "若已勾选但仍显示未授权：先退出 KeyCount，在系统设置中移除旧条目，重新添加“应用程序”内的当前副本，再打开 KeyCount。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        copyPermissionDiagnostics()
                    } label: {
                        Label("复制授权诊断信息", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    Text(diagnosticMessage ?? "包含运行路径、系统版本、签名与授权状态，不含输入内容。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PanelCard {
                VStack(alignment: .leading, spacing: 11) {
                    sectionTitle("关于统计", symbol: "text.word.spacing")
                    Text("敲键字符 = 敲出来的可打印字符数，拼音每个字母各算一次，所有应用都能统计。")
                    Text("上屏字数 = 实际上屏的字数，只增不减；净字数 = 上屏 − 删减，可能为负。中文按字、英文与数字按词。")
                    Text("只统计手打的字：每次文本变化都要有对应的按键，且不超过这段时间的按键所能产生的量。粘贴、撤销、AI 流式输出、文档加载与同步、切换文档都不计入，也不会倒扣。")
                    Text("速度为最近 60 秒的量。发送后清空不扣字数。语音输入与手写板没有按键，无法计入。统计为估算值，不等同于文档总字数。")
                    Text("Word、部分旧版 Electron 应用不向系统暴露可读文本，上屏与净字数统计不到；敲键字符不受影响。")
                    if snapshot.hasAccessibility {
                        Text(snapshot.hasInputMonitoring
                            ? "本次运行已跳过 \(snapshot.ignoredChanges.formatted()) 次非人工改动。"
                            : "未开启输入监控时无法核对按键，只能按体量粗略拦截，计数会偏松。")
                    }
                    Divider()
                    Button {
                        showDataFolder()
                    } label: {
                        Label("打开本机数据文件夹", systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    if let folderError {
                        Text(folderError).foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("KeyCount")
                Spacer()
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .onAppear { refreshLoginStatus() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshLoginStatus() }
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func preferenceToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func permissionRow(
        _ title: String, subtitle: String, granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("已开启", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            } else {
                Button("开启", action: action)
                    .controlSize(.small)
                    .disabled(!snapshot.launchLocation.allowsPermissionRequests)
                    .accessibilityLabel("开启\(title)权限")
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard snapshot.launchLocation.allowsPermissionRequests else {
            loginMessage = "请先将应用安装到“应用程序”，再设置登录启动。"
            return
        }
        do {
            try LaunchAtLogin.setEnabled(enabled)
            refreshLoginStatus()
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            loginMessage = "设置未生效：\(error.localizedDescription)"
        }
    }

    private func refreshLoginStatus() {
        launchAtLogin = LaunchAtLogin.isEnabled
        loginMessage = LaunchAtLogin.requiresApproval
            ? "请在系统设置 → 通用 → 登录项中允许 KeyCount。" : nil
    }

    private func showDataFolder() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyCount", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folderError = NSWorkspace.shared.open(url) ? nil : "未能打开文件夹，请稍后重试。"
        } catch {
            folderError = "未能打开文件夹：\(error.localizedDescription)"
        }
    }

    private func copyPermissionDiagnostics() {
        let report = PermissionDiagnostics.report()
        NSPasteboard.general.clearContents()
        diagnosticMessage = NSPasteboard.general.setString(report, forType: .string)
            ? "已复制。分享前可将运行路径中的用户名隐去。"
            : "复制失败，请重试。"
    }
}
