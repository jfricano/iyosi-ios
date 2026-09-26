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
    @State private var kinds = Set(PlaceKind.allCases)
    @State private var statuses: Set<AdvisoryStatus> = [.verifiedDesignated, .communityReported, .disputed]
    @State private var search = ""
    @State private var suggestions: [AddressSuggestion] = []
    @State private var searchError: String?
    @State private var mapError: String?
    @State private var loading = false
    @State private var moreAvailable = false

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
            ZStack(alignment: .bottom) {
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
                                else { Text("\(cluster.places.count)").font(.headline).foregroundStyle(.white).padding(11).background(.teal, in: Circle()) }
                            }
                            .accessibilityLabel(cluster.places.count == 1 ? "\(cluster.places[0].name), \(cluster.places[0].kind.title), \(cluster.places[0].advisoryStatus.title)" : "\(cluster.places.count) places, double tap to zoom")
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .onEnd) { context in region = context.region }

                VStack(alignment: .leading, spacing: 8) {
                    if loading { ProgressView("Loading places…").padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    if zoomLimited {
                        Text("Zoom in to load all places. The API limits each map request to 0.5° per side.")
                            .font(.footnote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let mapError {
                        Label(mapError, systemImage: "wifi.exclamationmark")
                            .font(.footnote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        Button("Retry") { Task { await loadMap() } }.buttonStyle(.borderedProminent)
                    } else if !loading && visiblePlaces.isEmpty {
                        Text("No places in this view. Pan the map or change filters.")
                            .font(.footnote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    } else if moreAvailable {
                        Text("Showing the first \(places.count) places in this view. Zoom in for more.")
                            .font(.footnote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Button { location.locate() } label: { Label("Near me", systemImage: "location") }
                        Spacer()
                        Button { showingAdd = true } label: { Label("Add place", systemImage: "plus") }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }.padding()
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search NCR address or landmark", text: $search)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Search NCR address or landmark")
                        if !search.isEmpty { Button { search = ""; suggestions = [] } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                    }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    if let searchError { Text(searchError).font(.footnote).foregroundStyle(.secondary) }
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading) {
                            ForEach(suggestions) { suggestion in
                                Button(suggestion.label) {
                                    position = .region(.init(center: suggestion.location.coordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
                                    search = ""; suggestions = []
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(.horizontal).padding(.top, 4)
            }
            .navigationTitle("iYosi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Filters", systemImage: "line.3.horizontal.decrease") { showingFilters = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Account", systemImage: "person.crop.circle") { showingAccount = true } }
            }
            .sheet(item: $selected) { PlaceDetailView(placeID: $0.id) }
            .sheet(isPresented: $showingAdd) { SubmissionView(initialPoint: GeoPoint(region.center)) }
            .sheet(isPresented: $showingAccount) { AccountView() }
            .sheet(isPresented: $showingFilters) { filtersSheet }
            .task(id: mapRequestKey) { await loadMap() }
            .task(id: search) { await searchAddress() }
            .onReceive(location.$point) { point in
                guard let point else { return }
                position = .region(.init(center: point.coordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
            }
            .onReceive(location.$message) { message in if let message { searchError = message } }
        }
    }

    private var filtersSheet: some View {
        NavigationStack {
            Form {
                Section("Place type") {
                    ForEach(PlaceKind.allCases) { kind in
                        Toggle(kind.title, isOn: Binding(get: { kinds.contains(kind) }, set: { enabled in
                            if enabled { kinds.insert(kind) } else { kinds.remove(kind) }
                        }))
                    }
                }
                Section("Advisory status") {
                    ForEach(AdvisoryStatus.allCases.filter { $0 != .closed }) { status in
                        Toggle(status.title, isOn: Binding(get: { statuses.contains(status) }, set: { enabled in
                            if enabled { statuses.insert(status) } else { statuses.remove(status) }
                        }))
                    }
                    Text("Prohibited places are warnings and have no directions.").font(.footnote)
                }
            }
            .navigationTitle("Map filters")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } } }
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
        suggestions = []; searchError = nil
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do { suggestions = try await state.api.suggestions(query) }
        catch {
            if !Task.isCancelled { searchError = (error as? APIError)?.code == "geocoder_unavailable" ? "Address search is not configured on this server." : error.localizedDescription }
        }
    }
}

private struct PlaceMarker: View {
    let place: PlaceSummary
    private var color: Color {
        switch place.advisoryStatus {
        case .verifiedDesignated: .teal
        case .communityReported: .blue
        case .disputed: .orange
        case .prohibited: .red
        case .closed: .gray
        }
    }
    var body: some View {
        Image(systemName: place.kind.symbol)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(9)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if place.advisoryStatus == .disputed || place.advisoryStatus == .prohibited {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.yellow)
                }
            }
            .shadow(radius: 3)
    }
}
