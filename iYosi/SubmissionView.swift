import MapKit
import SwiftUI

struct SubmissionView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let correcting: Place?
    @State private var pin: GeoPoint
    @State private var accessPoint: GeoPoint?
    @State private var position: MapCameraPosition
    @State private var selectingEntrance = false
    @State private var name: String
    @State private var kind: PlaceKind
    @State private var address: String
    @State private var notes: String
    @State private var insideVenue: Bool
    @State private var basis = ""
    @State private var nearby: [PlaceSummary] = []
    @State private var nearbyError: String?
    @State private var error: String?
    @State private var acknowledgement: Acknowledgement?
    @State private var busy = false
    @State private var key = UUID().uuidString
    @State private var lastPayload: Data?

    init(initialPoint: GeoPoint, correcting: Place? = nil) {
        self.correcting = correcting
        _pin = State(initialValue: correcting?.location ?? initialPoint)
        _accessPoint = State(initialValue: correcting?.accessPoint)
        _position = State(initialValue: .region(.init(center: (correcting?.location ?? initialPoint).coordinate, span: .init(latitudeDelta: 0.015, longitudeDelta: 0.015))))
        _name = State(initialValue: correcting?.name ?? "")
        _kind = State(initialValue: correcting?.kind ?? .informalOutdoor)
        _address = State(initialValue: correcting?.addressLabel ?? "")
        _notes = State(initialValue: correcting?.accessNotes ?? "")
        _insideVenue = State(initialValue: correcting?.insideVenue ?? false)
    }
    private var closeDuplicates: [PlaceSummary] {
        nearby.filter { candidate in
            candidate.id != correcting?.id && CLLocation(latitude: pin.lat, longitude: pin.lon)
                .distance(from: CLLocation(latitude: candidate.location.lat, longitude: candidate.location.lon)) < 50
        }
    }
    private var canSubmit: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && name.count <= 120 &&
        basis.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 && basis.count <= 1000 &&
        address.count <= 240 && notes.count <= 500 &&
        (correcting != nil || closeDuplicates.isEmpty) && !busy
    }

    var body: some View {
        NavigationStack {
            Group {
                if !state.isSignedIn { AuthView(embedded: true) }
                else if let acknowledgement { success(acknowledgement) }
                else { form }
            }
            .navigationTitle(correcting == nil ? "Propose a place" : "Suggest correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if state.isSignedIn && acknowledgement == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await submit() } } label: {
                            if busy { ProgressView() }
                            else { Text("Submit").fontWeight(.semibold) }
                        }.disabled(!canSubmit)
                    }
                }
            }
            .guideScreen()
        }
    }
    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    GuideEyebrow(text: correcting == nil ? "Share local knowledge" : "Help keep the guide current")
                    Text(correcting == nil ? "What did you find?" : "What has changed?")
                        .font(GuideTheme.editorial(28)).fixedSize(horizontal: false, vertical: true)
                    Text("Share what you observed. A community report does not establish permission to smoke.")
                        .font(GuideTheme.body(15, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                }.padding(.vertical, 6)
            }.listRowBackground(Color.clear)
            Section("Pin locations") {
                Text("Tap the map to place the \(selectingEntrance ? "public entrance" : "reported area") pin.")
                    .font(.footnote).foregroundStyle(GuideTheme.muted)
                MapReader { proxy in
                    Map(position: $position) {
                        Annotation("Reported area", coordinate: pin.coordinate) {
                            mapPin(symbol: "diamond.fill", color: GuideTheme.amber, background: GuideTheme.amberPale)
                        }
                        if let accessPoint {
                            Annotation("Public entrance", coordinate: accessPoint.coordinate) {
                                mapPin(symbol: "door.left.hand.open", color: GuideTheme.teal, background: GuideTheme.tealPale)
                            }
                        }
                    }
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        if selectingEntrance { accessPoint = GeoPoint(coordinate) }
                        else { pin = GeoPoint(coordinate) }
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(GuideTheme.line, lineWidth: 1) }
                .accessibilityLabel("Map for selecting the reported area or public entrance pin")
                Picker("Tap sets", selection: $selectingEntrance) {
                    Text("Reported area").tag(false)
                    Text("Public entrance").tag(true)
                }.pickerStyle(.segmented)
                if accessPoint != nil { Button("Remove entrance pin") { accessPoint = nil } }
                Text("Area: \(pin.lat.formatted(.number.precision(.fractionLength(5)))), \(pin.lon.formatted(.number.precision(.fractionLength(5))))")
                    .font(.caption.monospacedDigit()).foregroundStyle(GuideTheme.muted)
            }.listRowBackground(GuideTheme.surface)
            Section {
                TextField("Name or landmark", text: $name)
                Picker("Type", selection: $kind) { ForEach(PlaceKind.allCases) { Text($0.title).tag($0) } }
                if kind == .venueDesignated { Toggle("Inside establishment", isOn: $insideVenue) }
                TextField("Address label (optional)", text: $address)
                TextField("Access note (optional)", text: $notes, axis: .vertical)
                TextField("How do you know about this place?", text: $basis, axis: .vertical)
            } header: { Text("Place") } footer: {
                Text("Every proposal stays pending until an administrator reviews it. You cannot set evidence-reviewed designation.")
            }.listRowBackground(GuideTheme.surface)
            Section("Nearby possible duplicates") {
                if let nearbyError { Text(nearbyError).font(.footnote).foregroundStyle(GuideTheme.muted) }
                else if nearby.isEmpty { Text("No published places found within 200 m.").foregroundStyle(GuideTheme.muted) }
                ForEach(nearby) { candidate in
                    Label(candidate.name, systemImage: candidate.kind.symbol)
                }
                if !closeDuplicates.isEmpty && correcting == nil {
                    GuideNotice(text: "A place is within 50 m. Open that place and suggest a correction instead.", symbol: "diamond.fill", warning: true)
                }
            }.listRowBackground(GuideTheme.surface)
            if let error {
                Section { GuideNotice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .guideForm()
        .task(id: pin) { await checkNearby() }
    }
    private func mapPin(symbol: String, color: Color, background: Color) -> some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold)).foregroundStyle(color)
            .padding(10).background(background, in: Circle())
            .overlay { Circle().stroke(color, lineWidth: 2) }
    }
    private func success(_ result: Acknowledgement) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.largeTitle).foregroundStyle(GuideTheme.teal)
                    .padding(16).background(GuideTheme.tealPale, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                GuideEyebrow(text: "Thank you for contributing")
                Text("Proposal received.").font(GuideTheme.editorial(32)).fixedSize(horizontal: false, vertical: true)
                Text("Your proposal will stay pending until an administrator reviews it.")
                    .foregroundStyle(GuideTheme.muted)
                GuideFact(title: "Reference", value: result.id, symbol: "doc.text")
                    .textSelection(.enabled)
                GuideNotice(text: "A submission is not permission to smoke. Check the current status and access note before visiting.")
                Button("Done") { dismiss() }
                    .buttonStyle(GuideButtonStyle())
            }.guideCard().padding(20)
        }.guideScreen()
    }
    private func checkNearby() async {
        nearby = []; nearbyError = nil
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        do {
            let result = try await state.api.nearby(pin)
            nearby = result.items
        }
        catch { if !Task.isCancelled { nearbyError = error.localizedDescription } }
    }
    private func submit() async {
        busy = true; error = nil
        let payload = SubmissionRequest(intent: correcting == nil ? "create" : "correct", placeId: correcting?.id,
                                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                                        location: pin, accessPoint: accessPoint,
                                        addressLabel: address.isEmpty ? nil : address,
                                        accessNotes: notes.isEmpty ? nil : notes,
                                        insideVenue: kind == .venueDesignated ? insideVenue : nil,
                                        basis: basis.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(payload)
            if data != lastPayload { key = UUID().uuidString; lastPayload = data }
            acknowledgement = try await state.api.submit(payload, key: key)
        } catch {
            if let apiError = error as? APIError, apiError.code == "likely_duplicate" {
                self.error = "A nearby place already exists. Open that place and suggest a correction. \(error.localizedDescription)"
            } else { self.error = error.localizedDescription }
        }
        busy = false
    }
}
