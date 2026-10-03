#if DEBUG
import Foundation
import SwiftUI

/// Read-only, in-memory records for visual checks without a running backend.
/// Enabled only by explicit simulator launch environment; never compiled in Release.
enum DesignPreview {
    static var enabled: Bool { ProcessInfo.processInfo.environment["IYOSI_DESIGN_PREVIEW"] == "1" }
    static var screen: String? { enabled ? (ProcessInfo.processInfo.environment["IYOSI_DESIGN_SCREEN"] ?? "map") : nil }
    static var signedIn: Bool { enabled && ProcessInfo.processInfo.environment["IYOSI_DESIGN_SIGNED_IN"] == "1" }
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesignPreviewProtocol.self]
        return URLSession(configuration: configuration)
    }()
    static var reviewedSummary: PlaceSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // The fixture is defined alongside the production model and never reaches a server.
        return try! decoder.decode(PlaceSummary.self, from: JSONSerialization.data(withJSONObject: place("reviewed")))
    }

    static func place(_ id: String) -> [String: Any] {
        let status: String
        let name: String
        let kind: String
        let latitude: Double
        let longitude: Double
        switch id {
        case "reviewed":
            status = "verified_designated"; name = "Fictional courtyard area"
            kind = "public_designated"; latitude = 14.594; longitude = 120.985
        case "disputed":
            status = "disputed"; name = "Fictional riverside report"
            kind = "informal_outdoor"; latitude = 14.609; longitude = 120.975
        case "prohibited":
            status = "prohibited"; name = "Fictional prohibited area"
            kind = "venue_claim"; latitude = 14.58; longitude = 120.975
        case "closed":
            status = "closed"; name = "Fictional closed area"
            kind = "venue_designated"; latitude = 14.59; longitude = 121.01
        default:
            status = "community_reported"; name = "Fictional neighborhood report"
            kind = "informal_outdoor"; latitude = 14.587; longitude = 121.002
        }
        let restricted = status == "prohibited" || status == "closed"
        var result: [String: Any] = [
            "id": id, "name": name, "kind": kind, "advisory_status": status,
            "location": ["lat": latitude, "lon": longitude],
            "address_label": "Fictional design fixture · not a real destination",
            "inside_venue": false, "last_confirmed_at": "2026-10-01T09:00:00Z",
            "rating": ["average": 4.0, "count": 1], "freshness": "fresh",
            "updated_at": "2026-10-01T09:00:00Z", "version": 1,
            "directions_allowed": !restricted
        ]
        if !restricted {
            result["access_point"] = ["lat": latitude, "lon": longitude]
            result["access_notes"] = "Fictional access note for layout testing. Check current signs and venue rules. Do not travel to this sample coordinate."
        }
        if status == "verified_designated" {
            result["verification_reviewed_at"] = "2026-09-29T09:00:00Z"
            result["verification"] = ["reviewed_at": "2026-09-29T09:00:00Z", "public_source": "Synthetic design fixture only; no actual designation claim."]
        }
        return result
    }

    static func response(for request: URLRequest) -> (Int, Any) {
        guard request.httpMethod == "GET" else {
            return (403, ["code": "preview_read_only", "message": "This is a read-only design preview. No account or contribution is sent to a server."])
        }
        let path = request.url?.path ?? ""
        if path == "/v1/places" || path == "/v1/places/nearby" {
            let includeWarnings = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "include_prohibited" && $0.value == "true" } ?? false
            let ids = includeWarnings ? ["reviewed", "community", "disputed", "prohibited"] : ["reviewed", "community", "disputed"]
            return (200, ["items": ids.map(place)])
        }
        if path.hasSuffix("/reviews") {
            return (200, ["items": [["id": "fixture-review", "stars": 4, "body": "Fictional review for visual testing.", "created_at": "2026-10-01T09:00:00Z", "updated_at": "2026-10-01T09:00:00Z"]]])
        }
        if path.hasSuffix("/confirmations") {
            return (200, ["items": [["id": "fixture-observation", "observation": "still_there", "observed_at": "2026-10-01T09:00:00Z", "created_at": "2026-10-01T09:00:00Z"]]])
        }
        if path.hasPrefix("/v1/places/") { return (200, place(path.components(separatedBy: "/").last ?? "community")) }
        if path == "/v1/address-suggestions" {
            return (200, ["items": [["label": "Fictional preview district", "location": ["lat": 14.595, "lon": 120.984]]], "provider": "local"])
        }
        if path == "/v1/me" {
            return (200, ["id": "fixture-account", "email": "design-preview@iyosi.invalid", "role": "contributor", "adult_attested_at": "2026-10-01T09:00:00Z"])
        }
        if path == "/v1/me/place-submissions" { return (200, ["items": []]) }
        return (404, ["code": "preview_not_found", "message": "No fixture for this design preview."])
    }
}

private final class DesignPreviewProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, body) = DesignPreview.response(for: request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct DesignPreviewRoot: View {
    let screen: String
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch screen {
                case "welcome": AdultAccessView(accepted: .constant(false))
                case "account": AccountView()
                case "submission": SubmissionView(initialPoint: .init(lat: 14.595, lon: 120.984))
                case "list": MapHomeView(initiallyShowingList: true)
                case "map-card": MapHomeView(initialSelection: DesignPreview.reviewedSummary)
                case "reviewed", "community", "disputed", "prohibited", "closed": PlaceDetailView(placeID: screen)
                default: MapHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("FICTIONAL DESIGN PREVIEW · READ ONLY")
                .font(.caption2).dynamicTypeSize(.large).foregroundStyle(GuideTheme.paper)
                .padding(6).frame(maxWidth: .infinity).background(GuideTheme.ink)
        }
        .dynamicTypeSize(ProcessInfo.processInfo.environment["IYOSI_DESIGN_LARGE_TYPE"] == "1" ? .accessibility3 : .large)
    }
}
#endif
