import Foundation

// MARK: - /api1/rs/status

struct TrainStatus: Decodable {
    var speed: Double?
    var latitude: Double?
    var longitude: Double?
    var internet: String?
    var gpsStatus: String?
    var connectivity: Connectivity?
    var serviceLevel: String?
    var wagonClass: String?
    var trainType: String?
    var tzn: String?
}

struct Connectivity: Decodable {
    var currentState: String?
    var nextState: String?
    var remainingTimeSeconds: Double?
}

// MARK: - /api1/rs/tripInfo/trip

struct TripResponse: Decodable {
    var trip: Trip?
}

struct Trip: Decodable {
    var trainType: String?
    var vzn: String?
    var totalDistance: Double?
    var actualPosition: Double?
    var distanceFromLastStop: Double?
    var stopInfo: StopInfo?
    var stops: [Stop]?
}

struct StopInfo: Decodable {
    var scheduledNext: String?
    var actualNext: String?
    var actualLast: String?
    var finalStationName: String?
}

struct Stop: Decodable, Identifiable {
    var station: Station
    var timetable: Timetable?
    var track: Track?
    var info: StopStatus?
    var delayReasons: [DelayReason]?

    var id: String { station.evaNr ?? station.name }
}

struct Station: Decodable {
    var evaNr: String?
    var name: String
}

struct Timetable: Decodable {
    var scheduledArrivalTime: Double?
    var actualArrivalTime: Double?
    var arrivalDelay: String?
    var scheduledDepartureTime: Double?
    var actualDepartureTime: Double?
    var departureDelay: String?
}

struct Track: Decodable {
    var scheduled: String?
    var actual: String?
}

struct StopStatus: Decodable {
    var passed: Bool?
    var positionStatus: String?
    var distanceFromStart: Double?
}

struct DelayReason: Decodable, Hashable {
    var code: String?
    var text: String
}

// MARK: - Convenience

extension Stop {
    var scheduledArrival: Date? { Date(epochMillis: timetable?.scheduledArrivalTime) }
    var actualArrival: Date? { Date(epochMillis: timetable?.actualArrivalTime) }
    var scheduledDeparture: Date? { Date(epochMillis: timetable?.scheduledDepartureTime) }
    var actualDeparture: Date? { Date(epochMillis: timetable?.actualDepartureTime) }

    /// Best known arrival time (falls back to departure for the origin station).
    var expectedArrival: Date? { actualArrival ?? scheduledArrival ?? expectedDeparture }
    var expectedDeparture: Date? { actualDeparture ?? scheduledDeparture }
    var scheduledTime: Date? { scheduledArrival ?? scheduledDeparture }

    var arrivalDelayMinutes: Int? { parseDelay(timetable?.arrivalDelay) }
    var departureDelayMinutes: Int? { parseDelay(timetable?.departureDelay) }
    var delayMinutes: Int? { arrivalDelayMinutes ?? departureDelayMinutes }

    var isPassed: Bool { info?.passed ?? (info?.positionStatus == "passed") }

    var trackChanged: Bool {
        guard let actual = track?.actual, let scheduled = track?.scheduled,
              !actual.isEmpty, !scheduled.isEmpty else { return false }
        return actual != scheduled
    }

    var displayTrack: String? {
        if let actual = track?.actual, !actual.isEmpty { return actual }
        if let scheduled = track?.scheduled, !scheduled.isEmpty { return scheduled }
        return nil
    }
}

/// The API reports delays as strings like "+5" or "" (no delay).
private func parseDelay(_ raw: String?) -> Int? {
    guard let raw else { return nil }
    let cleaned = raw.filter { $0.isNumber || $0 == "-" }
    return cleaned.isEmpty ? nil : Int(cleaned)
}

extension Date {
    init?(epochMillis: Double?) {
        guard let ms = epochMillis, ms > 0 else { return nil }
        self.init(timeIntervalSince1970: ms / 1000)
    }
}
