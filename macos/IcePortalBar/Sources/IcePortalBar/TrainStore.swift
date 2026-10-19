import Foundation
import SwiftUI

struct SpeedSample: Identifiable {
    let date: Date
    let speed: Double
    var id: Date { date }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case speed, nextStop, delay, iconOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: return "Speed"
        case .nextStop: return "Next stop"
        case .delay: return "Delay"
        case .iconOnly: return "Icon only"
        }
    }
}

enum SettingsKey {
    static let menuBarDisplay = "menuBarDisplay"
    static let pollInterval = "pollInterval"
}

/// Polls the ICE Portal and exposes the current train state to the UI.
@MainActor
final class TrainStore: ObservableObject {
    @Published private(set) var status: TrainStatus?
    @Published private(set) var trip: Trip?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isRefreshing = false
    /// Rolling window of recent speeds, only used for the sparkline.
    @Published private(set) var speedHistory: [SpeedSample] = []

    private let client = PortalClient()
    private var pollTask: Task<Void, Never>?
    private let historyWindow: TimeInterval = 20 * 60

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.menuBarDisplay: MenuBarDisplay.speed.rawValue,
            SettingsKey.pollInterval: 10.0,
        ])
        start()
    }

    var isConnected: Bool { status != nil }

    private var pollInterval: TimeInterval {
        max(3, UserDefaults.standard.double(forKey: SettingsKey.pollInterval))
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.pollInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let client = self.client
        async let statusResult = try? client.status()
        async let tripResult = try? client.trip()
        let (newStatus, newTrip) = await (statusResult, tripResult)

        status = newStatus
        // Keep the last known trip if only the trip endpoint hiccups.
        if let newTrip { trip = newTrip } else if newStatus == nil { trip = nil }

        guard newStatus != nil || newTrip != nil else { return }
        let now = Date()
        lastUpdate = now
        if let speed = newStatus?.speed {
            speedHistory.append(SpeedSample(date: now, speed: speed))
            speedHistory.removeAll { now.timeIntervalSince($0.date) > historyWindow }
        }
    }

    // MARK: - Derived information

    var trainName: String? {
        if let type = trip?.trainType ?? status?.trainType, let number = trip?.vzn {
            return "\(type) \(number)"
        }
        return status?.trainType
    }

    var finalStation: String? {
        trip?.stopInfo?.finalStationName ?? trip?.stops?.last?.station.name
    }

    var stops: [Stop] { trip?.stops ?? [] }

    var nextStopIndex: Int? {
        let stops = self.stops
        if let next = trip?.stopInfo?.actualNext,
           let index = stops.firstIndex(where: { $0.station.evaNr == next }) {
            return index
        }
        return stops.firstIndex { !$0.isPassed }
    }

    var nextStop: Stop? { nextStopIndex.map { stops[$0] } }

    var upcomingStops: [Stop] {
        guard let index = nextStopIndex else { return [] }
        return Array(stops[index...])
    }

    /// Delay (in minutes) forecast for the next stop.
    var currentDelay: Int? { nextStop?.delayMinutes }

    /// Trip progress between 0 and 1.
    var progress: Double? {
        guard let total = trip?.totalDistance, total > 0 else { return nil }
        let position = (trip?.actualPosition ?? 0) + (trip?.distanceFromLastStop ?? 0)
        return min(1, max(0, position / total))
    }

    var distanceTravelledKm: Double? {
        guard let trip, trip.totalDistance != nil else { return nil }
        return ((trip.actualPosition ?? 0) + (trip.distanceFromLastStop ?? 0)) / 1000
    }

    var totalDistanceKm: Double? { trip?.totalDistance.map { $0 / 1000 } }

    /// When the connectivity is forecast to change, if known.
    var connectivityChangeDate: Date? {
        guard let seconds = status?.connectivity?.remainingTimeSeconds, seconds > 0,
              let lastUpdate else { return nil }
        return lastUpdate.addingTimeInterval(seconds)
    }

    var maxSpeed: Double? { speedHistory.map(\.speed).max() }

    /// Unique delay reasons across the remaining trip.
    var upcomingDelayReasons: [DelayReason] {
        var seen = Set<String>()
        return upcomingStops
            .flatMap { $0.delayReasons ?? [] }
            .filter { seen.insert($0.text).inserted }
    }

    func menuBarText(for display: MenuBarDisplay) -> String? {
        guard isConnected else { return nil }
        switch display {
        case .speed:
            return status?.speed.map { "\(Int($0.rounded())) km/h" }
        case .nextStop:
            guard let stop = nextStop else { return nil }
            if let arrival = stop.expectedArrival {
                let minutes = Int((arrival.timeIntervalSinceNow / 60).rounded(.up))
                if minutes > 0 { return "\(stop.station.name) · \(minutes) min" }
            }
            return stop.station.name
        case .delay:
            guard let delay = currentDelay else { return "On time" }
            return delay > 0 ? "+\(delay) min" : "On time"
        case .iconOnly:
            return nil
        }
    }
}
