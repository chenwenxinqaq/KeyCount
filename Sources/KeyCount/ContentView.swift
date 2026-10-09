import SwiftUI

/// Presentation snapshots let previews render without reading other apps or user data.
struct ContentView: View {
    @EnvironmentObject var monitor: KeyboardMonitor
    @EnvironmentObject var net: NetTextMonitor
    @EnvironmentObject var preferences: AppPreferences

    var body: some View {
        DashboardView(snapshot: snapshot, preferences: preferences)
    }

    private var snapshot: DashboardSnapshot {
        var days = HistoryStore.recentDays(7)
        if let index = days.indices.last, Calendar.current.isDateInToday(days[index].date) {
            days[index] = DayRecord(
                date: days[index].date, netChars: net.netChars, typed: net.added,
                chars: monitor.charCount, keys: monitor.keyCount
            )
        }
        return DashboardSnapshot(
            netChars: net.netChars, added: net.added, removed: net.removed,
            currentSpeed: net.currentSpeed, peakSpeed: net.peakSpeed,
            activeMinutes: net.activeMinutes, isIdle: net.idle,
            characterCount: monitor.charCount, keyCount: monitor.keyCount,
            keySpeed: monitor.keySpeed, keyPeakSpeed: monitor.peakKeySpeed,
            keyActiveMinutes: monitor.activeMinutes,
            ignoredChanges: net.ignoredChanges,
            hasAccessibility: net.hasPermission, hasInputMonitoring: monitor.hasPermission,
            hours: monitor.hourBuckets, days: days, launchLocation: AppInstallation.current
        )
    }
}
