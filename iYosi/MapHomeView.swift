import MapKit
import SwiftUI

private struct MapCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let places: [PlaceSummary]
}

struct MapHomeView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var location = ForegroundLocation()
    @State private var position: MapCameraPosition = .region(.init(center: .init(latitude: 14.595, longitude: 120.984), span: .init(latitudeDelta: 0.18, longitudeDelta: 0.18)))
    @State private var region = MKCoordinateRegion(center: .init(latitude: 14.595, longitude: 120.984), span: .init(latitudeDelta: 0.18, longitudeDelta: 0.18))
    @State private var places: [PlaceSummary] = []
    @State private var selected: PlaceSummary?
    @State private var showingAdd = false
    @State private var showingAccount = false
    @State private var showingFilters = false
    @State private var showingLegend = false
    @State private var showingList = false
    @State private var kinds = Set(PlaceKind.allCases)
    @State private var statuses: Set<AdvisoryStatus> = [.verifiedDesignated, .communityReported, .disputed]
    @State private var search = ""
    @State private var suggestions: [AddressSuggestion] = []
    @State private var suggestionProvider: String?
    @State private var searchError: String?
    @State private var mapError: String?
    @State private var loading = false
    @State private var moreAvailable = false

    init(initiallyShowingList: Bool = false, initialSelection: PlaceSummary? = nil) {
        _showingList = State(initialValue: initiallyShowingList)
        _selected = State(initialValue: initialSelection)
    }

    private var bbox: String {
        let halfLat = min(max(region.span.latitudeDelta, 0.005), 0.48) / 2
        let halfLon = min(max(region.span.longitudeDelta, 0.005), 0.48) / 2
        let west = max(-180, region.center.longitude - halfLon)
        let east = min(180, region.center.longitude + halfLon)
        let south = max(-90, region.center.latitude - halfLat)
        let north = min(90, region.center.latitude + halfLat)
        return "\(west),\(south),\(east),\(north)"
    }
    private var mapRequestKey: String { "\(state.baseURL)|\(bbox)|\(statuses.contains(.prohibited))" }
    private var zoomLimited: Bool { region.span.latitudeDelta > 0.5 || region.span.longitudeDelta > 0.5 }
    private var visiblePlaces: [PlaceSummary] { places.filter { kinds.contains($0.kind) && statuses.contains($0.advisoryStatus) } }
    private var clusters: [MapCluster] {
        let visible = visiblePlaces
        let cell = max(region.span.latitudeDelta, region.span.longitudeDelta) / 8
        guard cell > 0.005 else { return visible.map { MapCluster(id: $0.id, coordinate: $0.location.coordinate, places: [$0]) } }
        let grouped = Dictionary(grouping: visible) { place in
            "\(Int(floor(place.location.lat / cell))):\(Int(floor(place.location.lon / cell)))"
        }
        return grouped.map { key, items in
            let lat = items.map(\.location.lat).reduce(0, +) / Double(items.count)
            let lon = items.map(\.location.lon).reduce(0, +) / Double(items.count)
            return MapCluster(id: key, coordinate: .init(latitude: lat, longitude: lon), places: items)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Group {
                    if showingList { placeList }
                    else { map }
                }
                .overlay(alignment: .topLeading) {
                    if loading {
                        ProgressView("Loading places…").font(GuideTheme.body(13, relativeTo: .caption))
                            .padding(12).background(GuideTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .padding(14).accessibilityLabel("Loading places")
                    }
                }
                bottomBar
            }
            .guideScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) {
                PlacePeekView(summary: $0)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(GuideTheme.surface)
            }
            .sheet(isPresented: $showingAdd) { SubmissionView(initialPoint: GeoPoint(region.center)) }
            .sheet(isPresented: $showingAccount) { AccountView() }
            .sheet(isPresented: $showingFilters) { filtersSheet }
            .sheet(isPresented: $showingLegend) { legendSheet }
            .task(id: mapRequestKey) { await loadMap() }
            .task(id: search) { await searchAddress() }
            .onReceive(location.$point) { point in
                guard let point else { return }
                showingList = false
                position = .region(.init(center: point.coordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
            }
            .onReceive(location.$message) { message in if let message { searchError = message } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                GuideWordmark(size: 29, showPin: false)
                Spacer()
                Text("Metro Manila").font(GuideTheme.body(13, relativeTo: .caption))
                    .foregroundStyle(GuideTheme.muted)
                Button { showingAccount = true } label: {
                    Image(systemName: "person.crop.circle").font(.system(size: 24))
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Account")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(GuideTheme.teal).accessibilityHidden(true)
                TextField("Search an area or landmark", text: $search)
                    .font(GuideTheme.body(15, relativeTo: .subheadline))
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .accessibilityLabel("Search Metro Manila area or landmark")
                if !search.isEmpty {
                    Button { search = ""; suggestions = []; suggestionProvider = nil } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 13).frame(minHeight: 48)
                .background(GuideTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).stroke(GuideTheme.line, lineWidth: 1) }
            if let searchError {
                Text(searchError).font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !suggestions.isEmpty { searchResults }
            HStack(spacing: 10) {
                Picker("Browse view", selection: $showingList) {
                    Text("Map").tag(false)
                    Text("List").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 180)
                Spacer(minLength: 4)
                Button { showingFilters = true } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                        .font(GuideTheme.heading(13, relativeTo: .subheadline)).frame(minHeight: 44)
                }.accessibilityLabel("Place type and status filters")
            }
        }.padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    showingList = false
                    position = .region(.init(center: suggestion.location.coordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
                    search = ""; suggestions = []; suggestionProvider = nil
                } label: {
                    Label(suggestion.label, systemImage: "mappin")
                        .font(GuideTheme.body(14, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            }
            if suggestionProvider == "geoapify" {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { providerLinks }
                    VStack(alignment: .leading, spacing: 4) { providerLinks }
                }.font(.caption2).padding(.top, 8)
            }
        }.padding(12).background(GuideTheme.surface, in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private var providerLinks: some View {
        Link("Powered by Geoapify", destination: URL(string: "https://www.geoapify.com/")!)
        Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(clusters) { cluster in
                Annotation(cluster.places.count == 1 ? cluster.places[0].name : "\(cluster.places.count) places", coordinate: cluster.coordinate) {
                    Button {
                        if cluster.places.count == 1 { selected = cluster.places[0] }
                        else {
                            position = .region(.init(center: cluster.coordinate, span: .init(latitudeDelta: max(region.span.latitudeDelta / 2, 0.006), longitudeDelta: max(region.span.longitudeDelta / 2, 0.006))))
                        }
                    } label: {
                        if cluster.places.count == 1 { PlaceMarker(place: cluster.places[0]) }
                        else {
                            Text("\(cluster.places.count)").font(GuideTheme.heading(18))
                                .foregroundStyle(GuideTheme.paper).frame(width: 48, height: 48)
                                .background(GuideTheme.ink, in: Circle())
                                .overlay { Circle().stroke(GuideTheme.surface, lineWidth: 3) }
                        }
                    }.buttonStyle(.plain)
                    .accessibilityLabel(cluster.places.count == 1 ? "\(cluster.places[0].name), \(cluster.places[0].kind.title), \(cluster.places[0].advisoryStatus.guideTitle)" : "\(cluster.places.count) places, double tap to zoom")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in region = context.region }
        .overlay(alignment: .bottomTrailing) {
            Button { location.locate() } label: {
                Image(systemName: "location").font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(GuideTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(GuideTheme.line, lineWidth: 1) }
            }.accessibilityLabel("Near me, use my location").padding(16)
        }
    }

    private var placeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                GuideEyebrow(text: "Places in this map area")
                ForEach(visiblePlaces.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { place in
                    Button { selected = place } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text(place.name).font(GuideTheme.heading(21, relativeTo: .title3))
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(GuideTheme.teal)
                            }
                            Label(place.kind.title, systemImage: place.kind.symbol)
                                .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                            GuideStatusBadge(status: place.advisoryStatus)
                            GuideFact(title: "Last confirmation", value: DateText.display(place.lastConfirmedAt), symbol: "clock")
                        }.guideCard().multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(GuideTheme.paper)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let mapError {
                HStack(alignment: .top, spacing: 12) {
                    Label("Places could not load. Check your connection or API server.", systemImage: "wifi.exclamationmark")
                        .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.warning)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await loadMap() } }.font(GuideTheme.heading(13, relativeTo: .caption))
                }.accessibilityHint(mapError)
            } else if zoomLimited {
                Text("Zoom in for a closer look and more places.").font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
            } else if !loading && visiblePlaces.isEmpty {
                Text("No places in this area. Try another view or adjust your filters.")
                    .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
            } else if moreAvailable {
                Text("Showing \(places.count) places. Zoom in to see more.")
                    .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    GuideEyebrow(text: "Find. Read. Check.")
                    Button { showingLegend = true } label: {
                        Label("Know the status", systemImage: "info.circle")
                            .font(GuideTheme.body(13, relativeTo: .caption)).frame(minHeight: 44)
                    }
                }
                Spacer(minLength: 0)
                Button { showingAdd = true } label: { Label("Add place", systemImage: "plus") }
                    .buttonStyle(GuideButtonStyle())
            }
        }.padding(.horizontal, 20).padding(.vertical, 16)
            .background(GuideTheme.surface)
            .overlay(alignment: .top) { Rectangle().fill(GuideTheme.line).frame(height: 1) }
    }

    private var filtersSheet: some View {
        NavigationStack {
            Form {
                Section {
                    GuideEyebrow(text: "A map with context")
                    Text("Choose what you see.").font(GuideTheme.heading(25))
                    Text("Place type and evidence status are separate. A report does not establish permission.")
                        .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                }.listRowBackground(GuideTheme.surface)
                Section("Place type") {
                    ForEach(PlaceKind.allCases) { kind in
                        Toggle(isOn: Binding(get: { kinds.contains(kind) }, set: { enabled in
                            if enabled { kinds.insert(kind) } else { kinds.remove(kind) }
                        })) { Label(kind.title, systemImage: kind.symbol) }
                    }
                }.listRowBackground(GuideTheme.surface)
                Section("Evidence & status") {
                    ForEach(AdvisoryStatus.allCases.filter { $0 != .closed }) { status in
                        Toggle(isOn: Binding(get: { statuses.contains(status) }, set: { enabled in
                            if enabled { statuses.insert(status) } else { statuses.remove(status) }
                        })) {
                            Label(status.guideTitle, systemImage: status.guideSymbol)
                                .foregroundStyle(status.guideTextColor)
                        }
                    }
                    Text("Prohibited places appear as warnings. Directions are unavailable.").font(GuideTheme.body(13, relativeTo: .caption))
                }.listRowBackground(GuideTheme.surface)
            }.guideForm()
            .navigationTitle("Map filters").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } } }
        }.presentationBackground(GuideTheme.paper)
    }

    private var legendSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GuideEyebrow(text: "Clear by design")
                    Text("Every place,\nin context.").font(GuideTheme.heading(30))
                    Text("Read the type, evidence status, latest check, and access note before deciding where to go.")
                        .foregroundStyle(GuideTheme.muted)
                    ForEach(AdvisoryStatus.allCases) { status in
                        VStack(alignment: .leading, spacing: 10) {
                            GuideStatusBadge(status: status)
                            Text(statusExplanation(status)).font(GuideTheme.body(15, relativeTo: .subheadline))
                        }.guideCard()
                    }
                    Text("Evidence review is not official certification. Follow posted signs, venue rules, and local law; respect shared air.")
                        .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.guideScreen()
            .navigationTitle("Know the status").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingLegend = false } } }
        }
    }

    private func statusExplanation(_ status: AdvisoryStatus) -> String {
        switch status {
        case .verifiedDesignated: "Supporting evidence for this designation has been reviewed by the iYosi team. Check the evidence date and current signs."
        case .communityReported: "A community observation without verified designation evidence. It does not establish permission to smoke."
        case .disputed: "The information has been questioned. Read the warning and check current rules before visiting."
        case .prohibited: "Smoking is reported as prohibited. Directions are unavailable."
        case .closed: "This record is closed. Directions are unavailable."
        }
    }

    private func loadMap() async {
        loading = true; mapError = nil
        do {
            var all: [PlaceSummary] = []
            var cursor: String?
            var hasMore = false
            for _ in 0..<5 {
                let page = try await state.api.places(bbox: bbox, cursor: cursor, includeProhibited: statuses.contains(.prohibited))
                try Task.checkCancellation()
                all += page.items
                cursor = page.nextCursor
                hasMore = cursor != nil
                if cursor == nil { break }
            }
            places = all; moreAvailable = hasMore
        } catch is CancellationError { return }
        catch { mapError = error.localizedDescription; places = [] }
        loading = false
    }
    private func searchAddress() async {
        suggestions = []; suggestionProvider = nil; searchError = nil
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let result = try await state.api.suggestions(query)
            suggestions = result.items
            suggestionProvider = result.provider
        }
        catch {
            if !Task.isCancelled { searchError = (error as? APIError)?.code == "geocoder_unavailable" ? "Address search is not configured on this server." : error.localizedDescription }
        }
    }
}

/// The same status-first place card as the landing page, backed by live API details.
private struct PlacePeekView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let summary: PlaceSummary
    @State private var place: Place?
    @State private var error: String?
    @State private var showingDetail = false
    private var status: AdvisoryStatus { place?.advisoryStatus ?? summary.advisoryStatus }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    GuideEyebrow(text: "Every place, in context")
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close place card")
                }
                Text(place?.name ?? summary.name).font(GuideTheme.heading(23, relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Label((place?.kind ?? summary.kind).title, systemImage: (place?.kind ?? summary.kind).symbol)
                    .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                GuideStatusBadge(status: status)
                if status == .prohibited || status == .closed || status == .disputed {
                    GuideNotice(text: status == .prohibited ? "Smoking is reported as prohibited. Directions are unavailable." : status == .closed ? "This place is closed. Directions are unavailable." : "Information is disputed. Read the warning and current rules.", symbol: "exclamationmark.triangle", warning: true)
                }
                GuideFact(title: "Last confirmation", value: DateText.display(place != nil ? place?.lastConfirmedAt : summary.lastConfirmedAt), symbol: "clock")
                if let place {
                    if place.directionsAllowed {
                        GuideFact(title: "Access note", value: place.accessNotes ?? "No access note on record. Check posted signs and the current entrance.", symbol: "figure.walk")
                    }
                } else if let error {
                    GuideNotice(text: error, symbol: "wifi.exclamationmark", warning: true)
                    Button("Retry latest details") { Task { await load() } }
                } else { ProgressView("Checking latest access information…").font(.caption) }
                Divider().overlay(GuideTheme.line)
                Button { showingDetail = true } label: {
                    HStack {
                        Text(status == .communityReported ? "Read report details" : "View place details")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.frame(minHeight: 44).font(GuideTheme.heading(15, relativeTo: .subheadline))
                }
                if status == .communityReported {
                    Text("A report does not establish permission to smoke.").font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.muted)
                }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
        .font(GuideTheme.body()).foregroundStyle(GuideTheme.ink).tint(GuideTheme.tealInk)
        .background(GuideTheme.surface)
        .sheet(isPresented: $showingDetail) { PlaceDetailView(placeID: summary.id) }
        .task(id: summary.id) { await load() }
    }
    private func load() async {
        error = nil
        do { place = try await state.api.place(summary.id) }
        catch is CancellationError { return }
        catch { self.error = "Latest access information could not load. Read the details or retry." }
    }
}

private struct PlaceMarker: View {
    let place: PlaceSummary
    var body: some View {
        Image(systemName: place.advisoryStatus.guideSymbol)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(GuideTheme.paper)
            .frame(width: 44, height: 44)
            .background(place.advisoryStatus.guideColor, in: Circle())
            .overlay { Circle().stroke(GuideTheme.surface, lineWidth: 3) }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: place.kind.symbol).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(GuideTheme.ink).frame(width: 19, height: 19)
                    .background(GuideTheme.surface, in: Circle())
                    .overlay { Circle().stroke(GuideTheme.line, lineWidth: 1) }
                    .offset(x: 4, y: 3)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
