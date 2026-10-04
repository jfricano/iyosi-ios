import MapKit
import SwiftUI

private enum DetailSheet: Identifiable {
    case confirm, review, reportPlace, reportReview(String), correction, merged(String)
    var id: String {
        switch self {
        case .confirm: "confirm"
        case .review: "review"
        case .reportPlace: "report-place"
        case .reportReview(let id): "report-\(id)"
        case .correction: "correction"
        case .merged(let id): "merged-\(id)"
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .guideScreen()
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
                    if let place { SubmissionView(initialPoint: place.location, correcting: place) }
                case .merged(let id): PlaceDetailView(placeID: id)
                }
            }
            .task(id: placeID) { await load() }
        }
    }

    @ViewBuilder private func content(_ place: Place) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(place.name).font(GuideTheme.heading(27, relativeTo: .title))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Label(place.kind.title, systemImage: place.kind.symbol)
                        .font(GuideTheme.body(15, relativeTo: .subheadline))
                        .foregroundStyle(GuideTheme.muted)
                    GuideStatusBadge(status: place.advisoryStatus)
                    if let verification = place.verification {
                        Text("Evidence reviewed \(DateText.display(verification.reviewedAt))")
                            .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                    } else {
                        Text("No reviewed designation evidence on record.")
                            .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                    }
                    GuideFact(title: "Last confirmation", value: DateText.display(place.lastConfirmedAt), symbol: "clock")
                    if place.advisoryStatus == .verifiedDesignated {
                        GuideNotice(text: "Evidence reviewed is an advisory designation, not official certification. Check posted rules and current conditions.")
                    } else if place.advisoryStatus == .communityReported || place.advisoryStatus == .disputed {
                        GuideNotice(text: "This report does not establish permission to smoke here.", symbol: "exclamationmark.triangle", warning: place.advisoryStatus == .disputed)
                    }
                    if place.advisoryStatus == .prohibited {
                        GuideNotice(text: "Smoking is reported as prohibited here. No directions are provided.", symbol: "nosign", warning: true)
                    }
                    if place.advisoryStatus == .closed {
                        GuideNotice(text: "This place is closed. No directions are provided.", symbol: "xmark.circle", warning: true)
                    }
                    if let merged = place.mergedInto {
                        GuideNotice(text: "This place was merged into another record.", symbol: "arrow.triangle.merge")
                        Button("Open the current record") { sheet = .merged(merged) }
                            .font(GuideTheme.heading(15, relativeTo: .subheadline)).frame(minHeight: 44)
                    }
                }
                .guideCard()

                VStack(alignment: .leading, spacing: 18) {
                    GuideEyebrow(text: "Before you go")
                    if let notes = place.accessNotes, place.directionsAllowed {
                        GuideFact(title: "Access note", value: notes, symbol: "figure.walk")
                    }
                    if let address = place.addressLabel {
                        GuideFact(title: "Location", value: address, symbol: "mappin")
                    }
                    if let inside = place.insideVenue {
                        GuideFact(title: "Setting", value: inside ? "Inside establishment" : "Outside establishment", symbol: "building.2")
                    }
                    if let verification = place.verification {
                        GuideFact(title: "Public source", value: verification.publicSource, symbol: "doc.text")
                    }
                    Text(place.freshness == "fresh" ? "Recent community confirmation" : "No recent community confirmation")
                        .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                    if place.directionsAllowed {
                        Button { directions(to: place.accessPoint ?? place.location, name: place.name) } label: {
                            Label("Directions to public access point", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(GuideButtonStyle()).disabled(state.isDesignPreview)
                        if state.isDesignPreview {
                            Text("Directions are unavailable in this fictional preview.")
                                .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                        }
                    }
                }
                .guideCard()

                if place.advisoryStatus != .closed && place.mergedInto == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        GuideEyebrow(text: "Help keep the guide current")
                        Text("Share what you observed.").font(GuideTheme.editorial(23, relativeTo: .title2))
                        Text("Confirmations and ratings describe community experience. They do not grant permission.")
                            .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                        Button { sheet = .confirm } label: {
                            Label("Confirm an observation", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(GuideButtonStyle(secondary: true))
                        Button { sheet = .review } label: {
                            Label("Rate or review", systemImage: "star").frame(maxWidth: .infinity)
                        }.buttonStyle(GuideButtonStyle(secondary: true))
                        Button("Suggest correction") { sheet = .correction }
                        Button("Report issue") { sheet = .reportPlace }
                    }.guideCard()
                }

                VStack(alignment: .leading, spacing: 14) {
                    GuideEyebrow(text: "Community observations")
                    Text("Recent observations").font(GuideTheme.heading(22, relativeTo: .title2))
                    if confirmations.isEmpty {
                        Text("No observations yet.").foregroundStyle(GuideTheme.muted)
                    }
                    ForEach(confirmations) { item in
                        GuideFact(title: observationTitle(item.observation), value: DateText.display(item.observedAt), symbol: item.observation == "still_there" ? "checkmark.circle" : "exclamationmark.triangle")
                    }
                    if confirmationCursor != nil {
                        Button("More observations") { Task { await moreConfirmations() } }
                    }
                }
                .guideCard()

                VStack(alignment: .leading, spacing: 14) {
                    GuideEyebrow(text: "Community experience")
                    Text("Reviews").font(GuideTheme.heading(22, relativeTo: .title2))
                    Label("\(place.rating.average.map { String(format: "%.1f", $0) } ?? "—") / 5 · \(place.rating.count) reviews", systemImage: "star")
                        .font(GuideTheme.heading(15, relativeTo: .subheadline))
                    if reviews.isEmpty { Text("No reviews yet.").foregroundStyle(GuideTheme.muted) }
                    ForEach(reviews) { review in
                        Divider().overlay(GuideTheme.line)
                        VStack(alignment: .leading, spacing: 9) {
                            Label("\(review.stars) / 5 stars", systemImage: "star")
                                .font(GuideTheme.heading(16, relativeTo: .headline))
                            Text(DateText.display(review.updatedAt))
                                .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                            if let body = review.body { Text(body).fixedSize(horizontal: false, vertical: true) }
                            Button("Report review") { sheet = .reportReview(review.id) }
                                .font(GuideTheme.body(14, relativeTo: .subheadline))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if reviewCursor != nil { Button("More reviews") { Task { await moreReviews() } } }
                }
                .guideCard()
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
    }
    private func observationTitle(_ raw: String) -> String {
        switch raw { case "still_there": "Still there"; case "changed": "Changed"; case "gone": "Gone"; default: raw }
    }
    private func directions(to point: GeoPoint, name: String) {
        guard !state.isDesignPreview else { return }
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
    @Environment(\.dismiss) private var dismiss
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Group {
            if state.isSignedIn { content }
            else {
                NavigationStack {
                    AuthView(embedded: true)
                        .navigationTitle("Sign in to contribute")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                        }
                        .guideScreen()
                }
            }
        }
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
                Section {
                    GuideEyebrow(text: "Community observation")
                    Text("What did you see?").font(GuideTheme.editorial(26, relativeTo: .title2))
                    GuideNotice(text: "Confirmations describe existence and access, not permission or quality.")
                }.listRowBackground(GuideTheme.surface)
                Section {
                    Picker("Observation", selection: $observation) {
                        Text("Still there").tag("still_there")
                        Text("Changed").tag("changed")
                        Text("Gone").tag("gone")
                    }
                    DatePicker("Observed", selection: $date, in: Date().addingTimeInterval(-29 * 86400)...Date(), displayedComponents: [.date, .hourAndMinute])
                } header: { Text("Your observation") }
                    .listRowBackground(GuideTheme.surface)
                Section {
                    TextField("Suggested access-note correction (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    Text("\(notes.count) / 500 characters")
                        .font(GuideTheme.body(12, relativeTo: .caption))
                        .foregroundStyle(notes.count > 500 ? GuideTheme.warning : GuideTheme.muted)
                } header: { Text("Access note") }
                    .listRowBackground(GuideTheme.surface)
                if let error {
                    Section { GuideNotice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                        .listRowBackground(GuideTheme.surface)
                }
            }
            .guideForm()
            .navigationTitle("Confirm place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "Sending…" : "Send") { Task { await send() } }.disabled(busy || notes.count > 500) }
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
                Section {
                    GuideEyebrow(text: "Community experience")
                    Text("Share your experience.").font(GuideTheme.editorial(26, relativeTo: .title2))
                    GuideNotice(text: "Your rating is separate from confirmations and evidence review. A rating does not establish permission.")
                }.listRowBackground(GuideTheme.surface)
                Section {
                    Picker("Stars", selection: $stars) { ForEach(1...5, id: \.self) { Text("\($0) stars").tag($0) } }
                    TextField("Your experience (optional)", text: $bodyText, axis: .vertical)
                        .lineLimit(4...10)
                    Text("\(bodyText.count) / 1,000 characters")
                        .font(GuideTheme.body(12, relativeTo: .caption))
                        .foregroundStyle(bodyText.count > 1000 ? GuideTheme.warning : GuideTheme.muted)
                } header: { Text("Your review") }
                    .listRowBackground(GuideTheme.surface)
                if let error {
                    Section { GuideNotice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                        .listRowBackground(GuideTheme.surface)
                }
            }
            .guideForm()
            .navigationTitle("Rate place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "Saving…" : "Save") { Task { await save() } }.disabled(busy || bodyText.count > 1000) }
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
                Section {
                    GuideEyebrow(text: "Guide moderation")
                    Text("Help us check an issue.").font(GuideTheme.editorial(26, relativeTo: .title2))
                    GuideNotice(text: "Reports go to moderation. Your identity is not shown publicly.", symbol: "person.crop.circle.badge.checkmark")
                }.listRowBackground(GuideTheme.surface)
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons.indices, id: \.self) { index in Text(reasons[index].1).tag(reasons[index].0) }
                    }
                    TextField("Details (optional)", text: $detail, axis: .vertical)
                        .lineLimit(4...10)
                    Text("\(detail.count) / 1,000 characters")
                        .font(GuideTheme.body(12, relativeTo: .caption))
                        .foregroundStyle(detail.count > 1000 ? GuideTheme.warning : GuideTheme.muted)
                } header: { Text("Issue details") }
                    .listRowBackground(GuideTheme.surface)
                if let error {
                    Section { GuideNotice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                        .listRowBackground(GuideTheme.surface)
                }
            }
            .guideForm()
            .navigationTitle("Report \(targetType)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "Sending…" : "Send") { Task { await send() } }.disabled(busy || detail.count > 1000) }
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
