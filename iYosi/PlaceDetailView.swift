import MapKit
import SwiftUI

private enum DetailSheet: Identifiable {
    case confirm, review, reportPlace, reportReview(String), correction
    var id: String {
        switch self {
        case .confirm: "confirm"
        case .review: "review"
        case .reportPlace: "report-place"
        case .reportReview(let id): "report-\(id)"
        case .correction: "correction"
        }
    }
}

struct PlaceDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let placeID: String
    @State private var place: Place?
    @State private var reviews: [PublicReview] = []
    @State private var confirmations: [PublicConfirmation] = []
    @State private var reviewCursor: String?
    @State private var confirmationCursor: String?
    @State private var loading = true
    @State private var error: String?
    @State private var sheet: DetailSheet?

    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView("Loading place…") }
                else if let error { ContentUnavailableView(error, systemImage: "mappin.slash", description: Text("The place may be unavailable or the API may be offline.")) }
                else if let place { content(place) }
            }
            .navigationTitle(place?.name ?? "Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .sheet(item: $sheet, onDismiss: { Task { await load() } }) { action in
                switch action {
                case .confirm: AuthRequiredView { ConfirmationForm(placeID: placeID) }
                case .review: AuthRequiredView { ReviewForm(placeID: placeID) }
                case .reportPlace: AuthRequiredView { ReportForm(targetType: "place", targetID: placeID) }
                case .reportReview(let id): AuthRequiredView { ReportForm(targetType: "review", targetID: id) }
                case .correction:
                    if let place { AuthRequiredView { SubmissionView(initialPoint: place.location, correcting: place) } }
                }
            }
            .task(id: placeID) { await load() }
        }
    }

    @ViewBuilder private func content(_ place: Place) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(place.kind.title, systemImage: place.kind.symbol).font(.headline)
                    Label(place.advisoryStatus.title, systemImage: place.advisoryStatus == .verifiedDesignated ? "checkmark.seal" : "exclamationmark.circle")
                        .font(.headline)
                        .foregroundStyle(place.advisoryStatus == .prohibited || place.advisoryStatus == .closed ? Color.red : Color.primary)
                    if place.advisoryStatus == .communityReported || place.advisoryStatus == .disputed {
                        Text("This report does not establish permission to smoke here.").font(.subheadline)
                    }
                    if place.advisoryStatus == .prohibited { Text("Smoking is reported as prohibited here. No directions are provided.").font(.subheadline).foregroundStyle(.red) }
                    if place.advisoryStatus == .closed { Text("This place is closed. No directions are provided.").font(.subheadline).foregroundStyle(.red) }
                    if let merged = place.mergedInto { Text("This place was merged into \(merged).").font(.subheadline) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                if let address = place.addressLabel { Label(address, systemImage: "mappin") }
                if let inside = place.insideVenue { Text(inside ? "Inside establishment" : "Outside establishment") }
                if let notes = place.accessNotes, place.directionsAllowed { VStack(alignment: .leading) { Text("Access notes").font(.headline); Text(notes) } }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidence and freshness").font(.headline)
                    if let verification = place.verification {
                        Text("Evidence reviewed \(DateText.display(verification.reviewedAt))")
                        Text("Source: \(verification.publicSource)").font(.subheadline)
                    } else { Text("No verified designation evidence on record.") }
                    Text("Last confirmed: \(DateText.display(place.lastConfirmedAt))")
                    Text(place.freshness == "fresh" ? "Recent community confirmation" : "No recent community confirmation")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Rating: \(place.rating.average.map { String(format: "%.1f", $0) } ?? "—") / 5 from \(place.rating.count) reviews")
                }

                if place.directionsAllowed {
                    Button { directions(to: place.accessPoint ?? place.location, name: place.name) } label: {
                        Label("Directions to public access point", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }.buttonStyle(.borderedProminent)
                }
                if place.advisoryStatus != .closed && place.mergedInto == nil {
                    HStack {
                        Button("Confirm") { sheet = .confirm }.buttonStyle(.bordered)
                        Button("Rate or review") { sheet = .review }.buttonStyle(.bordered)
                    }
                    HStack {
                        Button("Suggest correction") { sheet = .correction }
                        Button("Report issue") { sheet = .reportPlace }
                    }.buttonStyle(.bordered)
                }

                Divider()
                Text("Recent observations").font(.title3.bold())
                if confirmations.isEmpty { Text("No observations yet.").foregroundStyle(.secondary) }
                ForEach(confirmations) { item in
                    Label("\(observationTitle(item.observation)) · \(DateText.display(item.observedAt))", systemImage: item.observation == "still_there" ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.subheadline)
                }
                if confirmationCursor != nil { Button("More observations") { Task { await moreConfirmations() } } }

                Divider()
                Text("Reviews").font(.title3.bold())
                if reviews.isEmpty { Text("No reviews yet.").foregroundStyle(.secondary) }
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(review.stars) / 5 stars · \(DateText.display(review.updatedAt))").font(.headline)
                        if let body = review.body { Text(body) }
                        Button("Report review") { sheet = .reportReview(review.id) }.font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
                if reviewCursor != nil { Button("More reviews") { Task { await moreReviews() } } }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
    }
    private func observationTitle(_ raw: String) -> String {
        switch raw { case "still_there": "Still there"; case "changed": "Changed"; case "gone": "Gone"; default: raw }
    }
    private func directions(to point: GeoPoint, name: String) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: point.coordinate))
        destination.name = name
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
    private func load() async {
        loading = true; error = nil
        do {
            let result = try await state.api.place(placeID)
            place = result
            if result.advisoryStatus != .closed && result.mergedInto == nil {
                let reviewPage = try? await state.api.reviews(placeID)
                let confirmationPage = try? await state.api.confirmations(placeID)
                reviews = reviewPage?.items ?? []; reviewCursor = reviewPage?.nextCursor
                confirmations = confirmationPage?.items ?? []; confirmationCursor = confirmationPage?.nextCursor
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func moreReviews() async {
        guard let reviewCursor, let page = try? await state.api.reviews(placeID, cursor: reviewCursor) else { return }
        reviews += page.items; self.reviewCursor = page.nextCursor
    }
    private func moreConfirmations() async {
        guard let confirmationCursor, let page = try? await state.api.confirmations(placeID, cursor: confirmationCursor) else { return }
        confirmations += page.items; self.confirmationCursor = page.nextCursor
    }
}

struct AuthRequiredView<Content: View>: View {
    @EnvironmentObject private var state: AppState
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Group { if state.isSignedIn { content } else { AuthView() } }
            .environmentObject(state)
    }
}

struct ConfirmationForm: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let placeID: String
    @State private var observation = "still_there"
    @State private var notes = ""
    @State private var date = Date()
    @State private var busy = false
    @State private var error: String?
    @State private var key = UUID().uuidString
    @State private var lastPayload: Data?
    @State private var receiptID = ""
    @State private var showingReceipt = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Observation", selection: $observation) {
                    Text("Still there").tag("still_there")
                    Text("Changed").tag("changed")
                    Text("Gone").tag("gone")
                }
                DatePicker("Observed", selection: $date, in: Date().addingTimeInterval(-30 * 86400)...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("Suggested access-note correction (optional)", text: $notes, axis: .vertical)
                Text("Confirmations describe existence and access, not permission or quality.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Confirm place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Send") { Task { await send() } }.disabled(busy || notes.count > 500) }
            }
            .alert("Confirmation recorded", isPresented: $showingReceipt) {
                Button("Done") { dismiss() }
            } message: { Text("Reference \(receiptID). This does not change the place's advisory status.") }
        }
    }
    private func send() async {
        busy = true; error = nil
        do {
            let payload = ConfirmationRequest(observation: observation, observedAt: ISO8601DateFormatter().string(from: date), accessNoteSuggestion: notes.isEmpty ? nil : notes)
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(payload)
            if data != lastPayload { key = UUID().uuidString; lastPayload = data }
            let receipt = try await state.api.confirm(placeID, payload: payload, key: key)
            receiptID = receipt.id; showingReceipt = true
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct ReviewForm: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let placeID: String
    @State private var stars = 3
    @State private var bodyText = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Stars", selection: $stars) { ForEach(1...5, id: \.self) { Text("\($0) stars").tag($0) } }
                TextField("Your experience (optional)", text: $bodyText, axis: .vertical)
                Text("Your rating is separate from confirmations and verification.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Rate place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy || bodyText.count > 1000) }
            }
        }
    }
    private func save() async {
        busy = true; error = nil
        do { _ = try await state.api.review(placeID, payload: .init(stars: stars, body: bodyText.isEmpty ? nil : bodyText)); dismiss() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct ReportForm: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let targetType: String
    let targetID: String
    @State private var reason = "wrong_status"
    @State private var detail = ""
    @State private var busy = false
    @State private var error: String?
    @State private var key = UUID().uuidString
    @State private var lastPayload: Data?
    @State private var receiptID = ""
    @State private var showingReceipt = false
    private let reasons = [("wrong_status", "Wrong status"), ("closed", "Closed"), ("access_notes", "Access notes"), ("privacy", "Privacy"), ("harassment", "Harassment"), ("spam", "Spam"), ("other", "Other")]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(reasons.indices, id: \.self) { index in Text(reasons[index].1).tag(reasons[index].0) }
                }
                TextField("Details (optional)", text: $detail, axis: .vertical)
                Text("Reports go to moderation. Your identity is not shown publicly.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Report \(targetType)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Send") { Task { await send() } }.disabled(busy || detail.count > 1000) }
            }
            .alert("Report received", isPresented: $showingReceipt) {
                Button("Done") { dismiss() }
            } message: { Text("Reference \(receiptID). Your report is in moderation.") }
        }
    }
    private func send() async {
        busy = true; error = nil
        do {
            let payload = ReportRequest(targetType: targetType, targetId: targetID, reason: reason, detail: detail.isEmpty ? nil : detail)
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(payload)
            if data != lastPayload { key = UUID().uuidString; lastPayload = data }
            let receipt = try await state.api.report(payload, key: key)
            receiptID = receipt.id; showingReceipt = true
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
