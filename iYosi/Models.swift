import CoreLocation
import Foundation

struct GeoPoint: Codable, Hashable {
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    init(_ coordinate: CLLocationCoordinate2D) { self.init(lat: coordinate.latitude, lon: coordinate.longitude) }
}

enum PlaceKind: String, Codable, CaseIterable, Identifiable {
    case publicDesignated = "public_designated"
    case venueDesignated = "venue_designated"
    case informalOutdoor = "informal_outdoor"
    case venueClaim = "venue_claim"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .publicDesignated: "Public designated area"
        case .venueDesignated: "Establishment designated area"
        case .informalOutdoor: "Community outdoor spot"
        case .venueClaim: "Establishment claim"
        }
    }
    var symbol: String {
        switch self {
        case .publicDesignated: "checkmark.seal.fill"
        case .venueDesignated: "building.2.fill"
        case .informalOutdoor: "leaf.fill"
        case .venueClaim: "questionmark.diamond.fill"
        }
    }
}

enum AdvisoryStatus: String, Codable, CaseIterable, Identifiable {
    case verifiedDesignated = "verified_designated"
    case communityReported = "community_reported"
    case disputed
    case prohibited
    case closed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .verifiedDesignated: "Verified designated"
        case .communityReported: "Community reported · unverified"
        case .disputed: "Disputed"
        case .prohibited: "Prohibited · warning"
        case .closed: "Closed"
        }
    }
}

struct Rating: Codable { let average: Double?; let count: Int }
struct Verification: Codable { let reviewedAt: String; let publicSource: String }

struct PlaceSummary: Codable, Identifiable {
    let id: String
    let name: String
    let kind: PlaceKind
    let advisoryStatus: AdvisoryStatus
    let location: GeoPoint
    let verificationReviewedAt: String?
    let lastConfirmedAt: String?
    let freshness: String
    let rating: Rating
    let updatedAt: String
    let directionsAllowed: Bool
}

struct Place: Codable, Identifiable {
    let id: String
    let name: String
    let kind: PlaceKind
    let advisoryStatus: AdvisoryStatus
    let location: GeoPoint
    let accessPoint: GeoPoint?
    let addressLabel: String?
    let accessNotes: String?
    let insideVenue: Bool?
    let verification: Verification?
    let lastConfirmedAt: String?
    let rating: Rating
    let updatedAt: String
    let version: Int
    let directionsAllowed: Bool
    let freshness: String
    let mergedInto: String?
}

struct Page<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

struct AddressSuggestion: Decodable, Identifiable {
    let label: String
    let location: GeoPoint
    var id: String { "\(label):\(location.lat):\(location.lon)" }
}
struct AddressSuggestions: Decodable {
    let items: [AddressSuggestion]
    let provider: String?
}

struct PublicReview: Decodable, Identifiable {
    let id: String
    let stars: Int
    let body: String?
    let createdAt: String
    let updatedAt: String
}
struct PublicConfirmation: Decodable, Identifiable {
    let id: String
    let observation: String
    let observedAt: String
    let createdAt: String
}
struct Account: Decodable {
    let id: String
    let email: String
    let role: String
    let adultAttestedAt: String
}
struct AuthToken: Decodable { let accessToken: String }
struct Acknowledgement: Decodable { let id: String; let state: String }
struct SubmissionStatus: Decodable, Identifiable {
    let id: String
    let intent: String
    let placeId: String?
    let name: String
    let kind: PlaceKind
    let state: String
    let decisionReason: String?
    let createdAt: String
    let decidedAt: String?
}
struct SubmissionList: Decodable { let items: [SubmissionStatus] }

struct SubmissionRequest: Encodable {
    let intent: String
    let placeId: String?
    let name: String
    let kind: PlaceKind
    let location: GeoPoint
    let accessPoint: GeoPoint?
    let addressLabel: String?
    let accessNotes: String?
    let insideVenue: Bool?
    let basis: String
}
struct ConfirmationRequest: Encodable {
    let observation: String
    let observedAt: String
    let accessNoteSuggestion: String?
}
struct ReviewRequest: Encodable { let stars: Int; let body: String? }
struct ReportRequest: Encodable {
    let targetType: String
    let targetId: String
    let reason: String
    let detail: String?
}
struct Credentials: Encodable { let email: String; let password: String }
struct Registration: Encodable { let email: String; let password: String; let adultAttested: Bool }

enum APIError: LocalizedError {
    case invalidServerURL
    case transport(String)
    case server(Int, String, String)
    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid HTTPS API URL, or a local HTTP URL for development."
        case .transport(let detail): "Could not reach the API. \(detail)"
        case .server(_, let message, _): message
        }
    }
    var code: String? { if case .server(_, _, let code) = self { code } else { nil } }
}
struct APIErrorBody: Decodable { let code: String; let message: String }

enum DateText {
    static func display(_ value: String?) -> String {
        guard let value else { return "No recent confirmation" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    static func now() -> String { ISO8601DateFormatter().string(from: .now) }
}
