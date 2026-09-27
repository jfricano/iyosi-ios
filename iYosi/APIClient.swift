import Foundation

struct APIClient {
    let baseURL: String
    let token: String?
    private let session: URLSession

    init(baseURL: String, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: (any Encodable)? = nil, idempotencyKey: String? = nil) async throws -> T {
        guard let root = URL(string: baseURL), let scheme = root.scheme?.lowercased(),
              ["http", "https"].contains(scheme), root.host != nil,
              (scheme == "https" || ["localhost", "127.0.0.1"].contains(root.host!.lowercased()) || root.host!.hasSuffix(".local")),
              var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else { throw APIError.invalidServerURL }
        let basePath = root.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = (basePath.isEmpty ? "" : "/" + basePath) + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidServerURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 15
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: urlRequest) }
        catch is CancellationError { throw CancellationError() }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Invalid response") }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw APIError.server(http.statusCode, error?.message ?? "Server returned \(http.statusCode).", error?.code ?? "http_error")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private struct AnyEncodable: Encodable {
        let value: any Encodable
        init(_ value: any Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }
    private func item(_ value: String, _ name: String) -> URLQueryItem { .init(name: name, value: value) }
    private func escaped(_ id: String) -> String { id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? id }

    func places(bbox: String, cursor: String? = nil, includeProhibited: Bool = false) async throws -> Page<PlaceSummary> {
        var query = [item(bbox, "bbox"), item("100", "limit")]
        if let cursor { query.append(item(cursor, "cursor")) }
        if includeProhibited { query.append(item("true", "include_prohibited")) }
        return try await request("/v1/places", query: query)
    }
    func place(_ id: String) async throws -> Place { try await request("/v1/places/\(escaped(id))") }
    func nearby(_ point: GeoPoint) async throws -> Page<PlaceSummary> {
        try await request("/v1/places/nearby", query: [item(String(point.lat), "lat"), item(String(point.lon), "lon"), item("200", "radius_m")])
    }
    func suggestions(_ query: String) async throws -> AddressSuggestions {
        try await request("/v1/address-suggestions", query: [item(query, "q")])
    }
    func reviews(_ id: String, cursor: String? = nil) async throws -> Page<PublicReview> {
        try await request("/v1/places/\(escaped(id))/reviews", query: cursor.map { [item($0, "cursor")] } ?? [])
    }
    func confirmations(_ id: String, cursor: String? = nil) async throws -> Page<PublicConfirmation> {
        try await request("/v1/places/\(escaped(id))/confirmations", query: cursor.map { [item($0, "cursor")] } ?? [])
    }
    func login(email: String, password: String) async throws -> AuthToken {
        try await request("/v1/auth/token", method: "POST", body: Credentials(email: email, password: password))
    }
    func register(email: String, password: String) async throws -> AuthToken {
        try await request("/v1/auth/register", method: "POST", body: Registration(email: email, password: password, adultAttested: true))
    }
    func me() async throws -> Account { try await request("/v1/me") }
    func submissions() async throws -> [SubmissionStatus] {
        let result: SubmissionList = try await request("/v1/me/place-submissions")
        return result.items
    }
    func submit(_ payload: SubmissionRequest, key: String) async throws -> Acknowledgement {
        try await request("/v1/place-submissions", method: "POST", body: payload, idempotencyKey: key)
    }
    func confirm(_ id: String, payload: ConfirmationRequest, key: String) async throws -> Acknowledgement {
        try await request("/v1/places/\(escaped(id))/confirmations", method: "POST", body: payload, idempotencyKey: key)
    }
    func review(_ id: String, payload: ReviewRequest) async throws -> PublicReview {
        try await request("/v1/places/\(escaped(id))/reviews/me", method: "PUT", body: payload)
    }
    func report(_ payload: ReportRequest, key: String) async throws -> Acknowledgement {
        try await request("/v1/reports", method: "POST", body: payload, idempotencyKey: key)
    }
    func deletionRequest() async throws -> Acknowledgement {
        try await request("/v1/me/deletion-requests", method: "POST")
    }
}
