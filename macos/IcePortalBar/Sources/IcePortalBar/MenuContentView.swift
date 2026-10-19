import AppKit
import Charts
import SwiftUI

// MARK: - Root

struct MenuContentView: View {
    @ObservedObject var store: TrainStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.isConnected {
                HeaderView(store: store)
                SpeedSection(store: store)
                if let stop = store.nextStop {
                    NextStopCard(stop: stop)
                }
                if let progress = store.progress {
                    TripProgressView(
                        progress: progress,
                        travelledKm: store.distanceTravelledKm,
                        totalKm: store.totalDistanceKm
                    )
                }
                ConnectivityRow(store: store)
                if store.upcomingStops.count > 1 {
                    LaterStopsView(stops: Array(store.upcomingStops.dropFirst()))
                }
                if !store.upcomingDelayReasons.isEmpty {
                    DelayReasonsView(reasons: store.upcomingDelayReasons)
                }
            } else {
                DisconnectedView()
            }
            Divider()
            FooterView(store: store)
        }
        .padding(14)
        .frame(width: 340)
    }
}

// MARK: - Sections

private struct HeaderView: View {
    @ObservedObject var store: TrainStore

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.trainName ?? "ICE")
                    .font(.headline)
                if let final = store.finalStation {
                    Text("→ \(final)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let wagonClass = store.status?.wagonClass {
                Text(wagonClassLabel(wagonClass))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
    }
}

private struct SpeedSection: View {
    @ObservedObject var store: TrainStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(store.status?.speed.map { "\(Int($0.rounded()))" } ?? "–")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.dbRed)
                        Text("km/h")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let max = store.maxSpeed {
                        Text("max \(Int(max.rounded())) km/h in the last 20 min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                DelayBadge(delay: store.currentDelay)
            }
            if store.speedHistory.count >= 2 {
                SpeedSparkline(samples: store.speedHistory)
            }
        }
    }
}

private struct SpeedSparkline: View {
    let samples: [SpeedSample]

    var body: some View {
        let top = max(300, samples.map(\.speed).max() ?? 0)
        Chart(samples) { sample in
            AreaMark(
                x: .value("Time", sample.date),
                y: .value("Speed", sample.speed)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.dbRed.opacity(0.35), Color.dbRed.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Time", sample.date),
                y: .value("Speed", sample.speed)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Color.dbRed)
        }
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0.0, 150.0, 300.0])
        }
        .frame(height: 56)
    }
}

private struct DelayBadge: View {
    let delay: Int?

    var body: some View {
        let minutes = max(0, delay ?? 0)
        let color = minutes > 0 ? Color.dbRed : Color.dbGreen
        Text(minutes > 0 ? "+\(minutes) min" : "On time")
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct NextStopCard: View {
    let stop: Stop

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT STOP")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(stop.station.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if let arrival = stop.expectedArrival {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(countdownText(to: arrival, now: context.date))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: 6) {
                if let scheduled = stop.scheduledTime {
                    if let expected = stop.expectedArrival, !isSameMinute(expected, scheduled) {
                        Text(clockTime(scheduled))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text(clockTime(expected))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.dbRed)
                    } else {
                        Text(clockTime(scheduled))
                    }
                }
                if let track = stop.displayTrack {
                    Text("·").foregroundStyle(.secondary)
                    Text("Platform \(track)")
                        .fontWeight(stop.trackChanged ? .semibold : .regular)
                        .foregroundStyle(stop.trackChanged ? Color.dbRed : Color.primary)
                    if stop.trackChanged, let old = stop.track?.scheduled {
                        Text("(was \(old))").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TripProgressView: View {
    let progress: Double
    let travelledKm: Double?
    let totalKm: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
                .tint(Color.dbRed)
            HStack {
                Text("\(Int((progress * 100).rounded()))% of trip")
                Spacer()
                if let travelledKm, let totalKm {
                    Text("\(Int(travelledKm)) / \(Int(totalKm)) km")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

private struct ConnectivityRow: View {
    @ObservedObject var store: TrainStore

    var body: some View {
        let current = store.status?.connectivity?.currentState ?? store.status?.internet
        HStack(spacing: 6) {
            Image(systemName: current == "UNSTABLE" || current == "NO_INFO" ? "wifi.exclamationmark" : "wifi")
                .foregroundStyle(internetColor(current))
            Text("Internet: \(internetLabel(current))")
            Spacer()
            if let next = store.status?.connectivity?.nextState, next != current,
               let changeDate = store.connectivityChangeDate {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    HStack(spacing: 4) {
                        Text("→")
                        Text(internetLabel(next))
                            .foregroundStyle(internetColor(next))
                        Text(countdownText(to: changeDate, now: context.date))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
    }
}

private struct LaterStopsView: View {
    let stops: [Stop]
    @State private var showAll = false
    private let collapsedCount = 5

    var body: some View {
        let visible = showAll ? stops : Array(stops.prefix(collapsedCount))
        VStack(alignment: .leading, spacing: 6) {
            Text("LATER STOPS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                ForEach(visible) { stop in
                    GridRow {
                        Text(clockTime(stop.scheduledTime))
                            .foregroundStyle(.secondary)
                        Text(stop.station.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(delayLabel(stop.delayMinutes))
                            .foregroundStyle((stop.delayMinutes ?? 0) > 0 ? Color.dbRed : Color.dbGreen)
                            .gridColumnAlignment(.trailing)
                        Text(stop.displayTrack ?? "")
                            .foregroundStyle(stop.trackChanged ? Color.dbRed : Color.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.callout)
            .monospacedDigit()
            if stops.count > collapsedCount {
                let title = showAll ? "Show fewer" : "Show all \(stops.count) stops"
                Button(title) {
                    showAll.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}

private struct DelayReasonsView: View {
    let reasons: [DelayReason]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(reasons, id: \.text) { reason in
                Label(reason.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DisconnectedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Not connected to WIFIonICE")
                .font(.headline)
            Text("Join the on-board Wi-Fi of a Deutsche Bahn ICE to see live train information.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct FooterView: View {
    @ObservedObject var store: TrainStore
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .speed
    @AppStorage(SettingsKey.pollInterval) private var pollInterval: Double = 10

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let lastUpdate = store.lastUpdate {
                    Text("Updated \(lastUpdate.formatted(date: .omitted, time: .standard))")
                } else {
                    Text(store.isRefreshing ? "Connecting…" : "Waiting for data…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh now")

            Menu {
                Picker("Menu Bar Shows", selection: $display) {
                    ForEach(MenuBarDisplay.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Update Every", selection: $pollInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
                Divider()
                Button("Open ICE Portal") {
                    if let url = URL(string: "https://iceportal.de") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Quit IcePortalBar") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Formatting helpers

extension Color {
    static let dbRed = Color(red: 0xEC / 255, green: 0x00 / 255, blue: 0x16 / 255)
    static let dbGreen = Color(red: 0x30 / 255, green: 0x97 / 255, blue: 0x00 / 255)
    static let dbAmber = Color(red: 0xD4 / 255, green: 0xA0 / 255, blue: 0x17 / 255)
    static let dbOrange = Color(red: 0xE8 / 255, green: 0x70 / 255, blue: 0x00 / 255)
}

private func internetColor(_ state: String?) -> Color {
    switch state {
    case "HIGH": return .dbGreen
    case "MIDDLE": return .dbAmber
    case "WEAK": return .dbOrange
    case "UNSTABLE": return .dbRed
    default: return .secondary
    }
}

private func internetLabel(_ state: String?) -> String {
    switch state {
    case "HIGH": return "Good"
    case "MIDDLE": return "Fair"
    case "WEAK": return "Weak"
    case "UNSTABLE": return "Unstable"
    default: return "Unknown"
    }
}

private func wagonClassLabel(_ wagonClass: String) -> String {
    switch wagonClass {
    case "FIRST": return "1st class"
    case "SECOND": return "2nd class"
    default: return wagonClass.capitalized
    }
}

private func delayLabel(_ minutes: Int?) -> String {
    guard let minutes, minutes != 0 else { return "+0" }
    return minutes > 0 ? "+\(minutes)" : "\(minutes)"
}

private func clockTime(_ date: Date?) -> String {
    date?.formatted(date: .omitted, time: .shortened) ?? "–"
}

private func isSameMinute(_ a: Date, _ b: Date) -> Bool {
    Int(a.timeIntervalSince1970 / 60) == Int(b.timeIntervalSince1970 / 60)
}

private func countdownText(to date: Date, now: Date) -> String {
    let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
    if minutes <= 0 { return "now" }
    if minutes < 60 { return "in \(minutes) min" }
    return "in \(minutes / 60) h \(minutes % 60) min"
}
