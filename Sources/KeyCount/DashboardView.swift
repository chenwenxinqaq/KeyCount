import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @ObservedObject var preferences: AppPreferences
    @State private var showingSettings = false
    @State private var chartPeriod = ChartPeriod.week
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ChartPeriod: String, CaseIterable {
        case week = "近 7 天"
        case today = "今日"
    }

    private var metric: PrimaryMetric { preferences.primaryMetric }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if showingSettings {
                    SettingsView(snapshot: snapshot, preferences: preferences)
                } else {
                    overview
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: max(280, min(650, (NSScreen.main?.visibleFrame.height ?? 850) - 130)))
            footer
        }
        .frame(width: 384)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.background)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: Theme.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 43, height: 43)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("KeyCount")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(showingSettings ? "偏好设置" : "每一次落笔，都算数。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            QuietIconButton(
                symbol: showingSettings ? "chevron.left" : "slider.horizontal.3",
                title: showingSettings ? "返回概览" : "偏好设置"
            ) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    showingSettings.toggle()
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    private var overview: some View {
        VStack(spacing: 12) {
            if snapshot.launchLocation != .applications {
                installationBanner
            }
            if !metric.isAuthorized(in: snapshot) && snapshot.launchLocation.allowsPermissionRequests {
                permissionBanner
            }
            todayCard
            speedCard
            chartCard
            keyboardSummary
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var todayCard: some View {
        let value = metric.value(in: snapshot)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(snapshot.status(for: metric))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(value.formatted())
                    .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                    .tracking(-2)
                    .foregroundStyle(value < 0 ? Theme.warning : Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(metric.title) \(value.formatted()) \(metric.unit)")
                Text(metric.unit).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(height: 52)

            secondaryMetrics

            if preferences.goalEnabled {
                goalProgress
            } else {
                Text(snapshot.date.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18).fill(Theme.accent.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.accent.opacity(0.13), lineWidth: 1)
        }
    }

    /// 主指标之外的两项，始终可见，方便对照
    private var secondaryMetrics: some View {
        HStack(spacing: 14) {
            switch metric {
            case .keystrokes:
                Label("上屏 \(snapshot.added.formatted()) 字", systemImage: "square.and.pencil")
                Label("净 \(snapshot.netChars.formatted()) 字", systemImage: "plusminus")
            case .typed:
                Label("敲键 \(snapshot.characterCount.formatted()) 字符", systemImage: "keyboard")
                Label("删减 \(snapshot.removed.formatted()) 字", systemImage: "minus")
            case .net:
                Label("新增 \(snapshot.added.formatted())", systemImage: "plus")
                Label("删减 \(snapshot.removed.formatted())", systemImage: "minus")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var goalProgress: some View {
        let progress = CountFormatting.goalProgress(
            count: metric.value(in: snapshot), goal: preferences.dailyGoal)
        let reached = progress >= 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    reached ? "今日目标已达成" : "每日目标",
                    systemImage: reached ? "checkmark.circle.fill" : "scope"
                )
                Spacer()
                Text("\(preferences.dailyGoal.formatted()) \(metric.unit) · \(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(reached ? Theme.accent : Color.secondary)

            GeometryReader { proxy in
                Capsule().fill(Theme.accent.opacity(0.10))
                Capsule().fill(Theme.accent)
                    .frame(width: proxy.size.width * progress)
            }
            .frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("每日目标进度")
            .accessibilityValue("\(Int(progress * 100))%，目标 \(preferences.dailyGoal) \(metric.unit)")
        }
        .padding(.top, 2)
    }

    private var speedCard: some View {
        let idle = metric.isIdle(in: snapshot)
        return PanelCard(padding: 14) {
            HStack(spacing: 0) {
                speedMetric(
                    "当前速度", value: idle || !metric.isAuthorized(in: snapshot)
                        ? "—" : metric.currentSpeed(in: snapshot).formatted(),
                    unit: metric.speedUnit, emphasized: !idle
                )
                Divider().frame(height: 38)
                speedMetric("今日峰值", value: metric.peakSpeed(in: snapshot).formatted(),
                            unit: metric.speedUnit)
                Divider().frame(height: 38)
                speedMetric("活跃时间", value: metric.activeMinutes(in: snapshot).formatted(),
                            unit: "分钟")
            }
        }
    }

    private func speedMetric(_ title: String, value: String, unit: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(emphasized ? Theme.accent : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private var chartCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(chartPeriod == .week ? "\(metric.shortTitle)趋势" : "键盘活动")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("时间范围", selection: $chartPeriod) {
                        ForEach(ChartPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 136)
                    .controlSize(.small)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text((chartPeriod == .week
                        ? snapshot.weeklyTotal(for: metric) : snapshot.keyCount).formatted())
                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(chartPeriod == .week
                        ? "\(metric.unit) · 近七天累计" : "次 · 今日总按键")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                ActivityChart(
                    points: chartPeriod == .week ? weekPoints : hourPoints,
                    unit: chartPeriod == .week ? metric.unit : "次",
                    emptyText: chartPeriod == .week
                        ? "从第一句话开始，积累会慢慢出现"
                        : (snapshot.hasInputMonitoring ? "今天还没有键盘活动" : "开启输入监控后显示活动分布")
                )
                .id(chartPeriod)
            }
        }
    }

    /// 底部一行：另一套引擎的状态。缺权限时给出设置入口，齐备时补充按键总量。
    private var keyboardSummary: some View {
        let needsText = metric.needsInputMonitoring
        let ready = needsText ? snapshot.hasAccessibility : snapshot.hasInputMonitoring
        return HStack(spacing: 6) {
            Image(systemName: needsText ? "text.word.spacing" : "keyboard")
            if ready {
                Text("总按键 \(snapshot.keyCount.formatted())")
                Text("·")
                Text("已跳过 \(snapshot.ignoredChanges.formatted()) 次非人工改动")
            } else {
                Text(needsText ? "字数统计未开启" : "按键统计未开启")
                Spacer()
                Button("设置") { showingSettings = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(needsText ? "设置辅助功能权限" : "设置输入监控权限")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    private var permissionBanner: some View {
        let needsInput = metric.needsInputMonitoring
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("授权后，开始记录你的积累")
                    .font(.system(size: 11, weight: .semibold))
                Text(needsInput
                    ? "输入监控用于在本机统计敲键次数，不保存按键内容。"
                    : "辅助功能用于在本机计算字数变化，不保存原文。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(needsInput ? "开启输入监控 →" : "开启辅助功能 →") {
                    if needsInput {
                        AppActions.openInputMonitoringSettings()
                    } else {
                        AppActions.openAccessibilitySettings()
                    }
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private var installationBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                snapshot.launchLocation == .readOnlyVolume ? "请先安装，再开启统计" : "建议从应用程序文件夹启动",
                systemImage: "externaldrive.badge.exclamationmark"
            )
            .font(.system(size: 11, weight: .semibold))
            Text("将 KeyCount 拖入“应用程序”，退出当前副本，再从“应用程序”打开后授权。不要直接从 DMG 运行。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开应用程序文件夹", action: AppActions.openApplicationsFolder)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield")
            Text("本机统计 · 不保存原文")
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .help("退出 KeyCount")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 21)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var statusColor: Color {
        if snapshot.launchLocation == .readOnlyVolume { return Theme.warning }
        if !metric.isAuthorized(in: snapshot) { return Theme.warning }
        return metric.isIdle(in: snapshot) ? .secondary : Theme.accent
    }

    private var weekPoints: [ActivityPoint] {
        snapshot.days.enumerated().map { index, day in
            let today = Calendar.current.isDate(day.date, inSameDayAs: snapshot.date)
            return ActivityPoint(
                id: index, label: today ? "今天" : Self.weekday(day.date),
                detail: day.date.formatted(.dateTime.month().day()),
                value: metric.value(in: day), highlighted: today
            )
        }
    }

    private var hourPoints: [ActivityPoint] {
        (0..<24).map { hour in
            ActivityPoint(
                id: hour, label: [0, 6, 12, 18, 23].contains(hour) ? "\(hour)" : "",
                detail: String(format: "%02d:00–%02d:00", hour, hour + 1),
                value: snapshot.hours.indices.contains(hour) ? snapshot.hours[hour] : 0,
                highlighted: hour == Calendar.current.component(.hour, from: snapshot.date)
            )
        }
    }

    private static func weekday(_ date: Date) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: date) - 1]
    }
}
