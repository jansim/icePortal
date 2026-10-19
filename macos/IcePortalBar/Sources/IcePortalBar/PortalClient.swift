import Foundation

/// Minimal client for the ICE Portal's internal APIs. These are only reachable
/// while connected to the on-board `WIFIonICE` network.
struct PortalClient {
    private let baseURL = URL(string: "https://iceportal.de/api1/rs/")!
    private let session: URLSession

    init(timeout: TimeInterval = 8) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func status() async throws -> TrainStatus {
        try await get("status")
    }

    func trip() async throws -> Trip? {
        let response: TripResponse = try await get("tripInfo/trip")
        return response.trip
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
