import SwiftUI

struct SearchView: View {
    @State private var term: String = ""
    @FocusState private var fieldFocused: Bool

    @State private var results = SearchService.SearchResults()
    @State private var isSearching = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var recentSearches: [String] = SearchView.loadRecents()
    @State private var selectedTab: SearchTab = .top

    @EnvironmentObject var queue: QueueManager

    enum SearchTab: String, CaseIterable {
        case top = "Top"
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed header: title + search bar
                VStack(alignment: .leading, spacing: 16) {
                    Text("Search")
                        .font(.display(40))
                        .foregroundStyle(Color.mmForeground)
                        .padding(.horizontal, 20)

                    searchBar
                        .padding(.horizontal, 20)

                    if !trimmed.isEmpty {
                        tabPicker
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, trimmed.isEmpty ? 0 : 8)

                // Scrollable body
                if trimmed.isEmpty {
                    emptyOrRecents
                } else {
                    pagedResults
                }
            }
            .background(Color.clear)
            .navigationBarHidden(true)
            .onChange(of: term) { _ in debounceSearch() }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        }
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
    }

    private var trimmed: String { term.trimmingCharacters(in: .whitespaces) }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.mmMutedFg)
            TextField("", text: $term)
                .placeholder(when: term.isEmpty) {
                    Text("Songs, artists, albums")
                        .foregroundStyle(Color.mmMutedFg)
                }
                .font(.system(size: 15))
                .foregroundStyle(Color.mmForeground)
                .autocapitalization(.none)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { recordRecent(term); runSearch() }
            if !term.isEmpty {
                if isSearching {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { term = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.mmMutedFg)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.mmMuted.opacity(0.7))
        .clipShape(Capsule())
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchTab.allCases, id: \.self) { tab in
                    let active = selectedTab == tab
                    Button { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab } } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.mmBackground : Color.mmForeground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(active ? Color.mmForeground : Color.mmSurface)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Paged results

    @ViewBuilder
    private var pagedResults: some View {
        let hasResults = !results.tracks.isEmpty || !results.albums.isEmpty || !results.artists.isEmpty
        if !hasResults && !isSearching {
            Text("No results for \"\(trimmed)\"")
                .font(.system(size: 14))
                .foregroundStyle(Color.mmMutedFg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, 64)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .top:    topSection
                    case .songs:  songsSection
                    case .albums: albumsSection
                    case .artists: artistsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 160)
            }
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !results.tracks.isEmpty {
                sectionBlock(title: "Songs") {
                    VStack(spacing: 4) {
                        ForEach(results.tracks.prefix(5)) { t in
                            trackRow(t)
                        }
                    }
                }
            }
            if !results.albums.isEmpty {
                sectionBlock(title: "Albums") {
                    VStack(spacing: 4) {
                        ForEach(results.albums.prefix(3)) { a in
                            NavigationLink(value: a) { albumRow(a) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !results.artists.isEmpty {
                sectionBlock(title: "Artists") {
                    VStack(spacing: 4) {
                        ForEach(results.artists.prefix(3)) { ar in
                            NavigationLink(value: ar) { artistRow(ar) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var songsSection: some View {
        VStack(spacing: 4) {
            ForEach(results.tracks) { t in trackRow(t) }
        }
    }

    private var albumsSection: some View {
        VStack(spacing: 4) {
            ForEach(results.albums) { a in
                NavigationLink(value: a) { albumRow(a) }.buttonStyle(.plain)
            }
        }
    }

    private var artistsSection: some View {
        VStack(spacing: 4) {
            ForEach(results.artists) { ar in
                NavigationLink(value: ar) { artistRow(ar) }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Row helpers

    private func trackRow(_ t: Track) -> some View {
        let isYt = t.videoId != nil && t.itunesTrackId < 0
        return TrackRow(
            track: t,
            onTap: {
                recordRecent(term)
                Task { await queue.playNow([t]) }
            },
            onAddToQueue: { queue.addToQueue(t) },
            accessory: isYt ? AnyView(ytBadge) : nil
        )
    }

    private var ytBadge: some View {
        Text("YT")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.mmMutedFg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.mmSurface)
            .clipShape(Capsule())
    }

    private func albumRow(_ a: Album) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: a.artworkUrl, size: 48, seedOverride: ArtTile.seed(from: a.id))
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.mmForeground).lineLimit(1)
                Text(a.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mmMutedFg).lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
    }

    private func artistRow(_ ar: Artist) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.mmSurface)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "person.fill").foregroundStyle(Color.mmMutedFg))
            Text(ar.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.mmForeground).lineLimit(1)
            Spacer()
        }
        .padding(8)
    }

    @ViewBuilder
    private func sectionBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .regular))
                .tracking(2)
                .foregroundStyle(Color.mmMutedFg)
            content()
        }
    }

    // MARK: - Empty / Recents

    @ViewBuilder
    private var emptyOrRecents: some View {
        if recentSearches.isEmpty {
            Text("Search for any song, artist, or album.")
                .font(.system(size: 14))
                .foregroundStyle(Color.mmMutedFg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, 64)
                .padding(.horizontal, 20)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recentSearches, id: \.self) { q in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color.mmSurface)
                                Image(systemName: "clock").foregroundStyle(Color.mmMutedFg)
                            }
                            .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.mmForeground)
                                Text("Recent")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mmMutedFg)
                            }
                            Spacer()
                            Button { removeRecent(q) } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(Color.mmMutedFg)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                        .onTapGesture { term = q; runSearch() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 160)
            }
        }
    }

    // MARK: - Search lifecycle

    private func debounceSearch() {
        debounceTask?.cancel()
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { results = SearchService.SearchResults(); return }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await MainActor.run { runSearch() }
        }
    }

    private func runSearch() {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = SearchService.SearchResults(); return }
        isSearching = true
        Task {
            let r = await SearchService.shared.search(q)
            await MainActor.run {
                results = r
                isSearching = false
                // Fire prefetch for top tracks so they're warm by the time user taps
                let top = Array(r.tracks.prefix(10))
                if !top.isEmpty {
                    Task {
                        await firePrefetch(tracks: top)
                    }
                }
            }
        }
    }

    private func firePrefetch(tracks: [Track]) async {
        guard let baseURLStr = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_FREE_BACKEND_URL") as? String,
              !baseURLStr.isEmpty,
              let baseURL = URL(string: baseURLStr) else { return }
        let url = baseURL.appendingPathComponent("prefetch")
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["tracks": tracks.map { t -> [String: Any?] in
            ["videoId": t.videoId as Any?, "itunesTrackId": t.itunesTrackId,
             "title": t.name, "artist": t.artistName, "isrc": t.isrc as Any?]
        }]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Recent searches

    private static let recentsKey = "searchView.recent.v1"
    private static func loadRecents() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }
    private static func saveRecents(_ values: [String]) {
        UserDefaults.standard.set(values, forKey: recentsKey)
    }
    private func recordRecent(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var list = recentSearches
        list.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        list.insert(q, at: 0)
        if list.count > 8 { list.removeLast(list.count - 8) }
        recentSearches = list
        Self.saveRecents(list)
    }
    private func removeRecent(_ q: String) {
        recentSearches.removeAll { $0 == q }
        Self.saveRecents(recentSearches)
    }
}

// MARK: - Placeholder modifier

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow { placeholder() }
            self
        }
    }
}
