import SwiftUI

struct SearchView: View {
    @State private var term: String = ""
    @FocusState private var fieldFocused: Bool

    @State private var tracks: [Track] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var debounceTask: Task<Void, Never>?

    @State private var recentSearches: [String] = SearchView.loadRecents()

    @EnvironmentObject var queue: QueueManager

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchBar
                    if term.trimmingCharacters(in: .whitespaces).isEmpty {
                        recentsSection
                    } else {
                        resultsScroll
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 48)
            }
            .navigationBarHidden(true)
            .onChange(of: term) { _ in debounceSearch() }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        }
    }

    // MARK: - Header

    private var header: some View {
        Text("Search")
            .font(AppTheme.text(30, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 16)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink3)
                TextField("What do you want to listen to?", text: $term)
                    .font(AppTheme.text(15))
                    .foregroundStyle(.black)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit { recordRecent(term); runSearch() }
                if !term.isEmpty {
                    Button { term = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.ink3)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white)
            .clipShape(Capsule())

            if fieldFocused {
                Button("Cancel") {
                    term = ""
                    fieldFocused = false
                }
                .font(AppTheme.text(15, weight: .medium))
                .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
    }

    // MARK: - Recents

    private var recentsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !recentSearches.isEmpty {
                    Text("Recent Searches")
                        .font(AppTheme.text(20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(recentSearches, id: \.self) { q in
                            recentRow(q)
                        }
                    }
                }
                Color.clear.frame(height: 160)
            }
        }
    }

    private func recentRow(_ query: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface)
                Image(systemName: "clock")
                    .foregroundStyle(AppTheme.ink2)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(query)
                    .font(AppTheme.text(15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("Recent")
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer()
            Button { removeRecent(query) } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AppTheme.ink2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            term = query
            runSearch()
        }
    }

    // MARK: - Results

    private var resultsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !tracks.isEmpty {
                    resultsGroup(title: "Songs") {
                        ForEach(tracks) { t in
                            TrackRow(
                                track: t,
                                onTap: {
                                    recordRecent(term)
                                    Task { await queue.playNow([t]) }
                                },
                                onAddToQueue: { queue.addToQueue(t) }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                }
                if !albums.isEmpty {
                    resultsGroup(title: "Albums") {
                        ForEach(albums) { a in
                            NavigationLink(value: a) { albumRow(a) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !artists.isEmpty {
                    resultsGroup(title: "Artists") {
                        ForEach(artists) { ar in
                            NavigationLink(value: ar) { artistRow(ar) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if tracks.isEmpty && albums.isEmpty && artists.isEmpty {
                    Text("No results yet — keep typing.")
                        .font(AppTheme.text(13))
                        .foregroundStyle(AppTheme.ink2)
                        .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 160)
            }
        }
    }

    @ViewBuilder
    private func resultsGroup<Content: View>(title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.text(20, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 16)
            content()
        }
    }

    private func albumRow(_ a: Album) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: a.artworkUrl, size: 44, seedOverride: ArtTile.seed(from: a.id))
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink).lineLimit(1)
                Text(a.artistName)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2).lineLimit(1)
            }
            Spacer()
        }.padding(.horizontal, 16)
    }

    private func artistRow(_ ar: Artist) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppTheme.surface)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(AppTheme.ink2)
                )
            Text(ar.name)
                .font(AppTheme.text(14, weight: .semibold))
                .foregroundStyle(AppTheme.ink).lineLimit(1)
            Spacer()
        }.padding(.horizontal, 16)
    }

    // MARK: - Search lifecycle

    private func debounceSearch() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            runSearch()
        }
    }

    private func runSearch() {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { tracks = []; albums = []; artists = []; return }
        Task {
            async let t = (try? await iTunesClient.shared.searchTracks(q))  ?? []
            async let al = (try? await iTunesClient.shared.searchAlbums(q)) ?? []
            async let ar = (try? await iTunesClient.shared.searchArtists(q)) ?? []
            let (tv, av, arv) = await (t, al, ar)
            await MainActor.run {
                tracks = tv
                albums = av
                artists = arv
            }
        }
    }

    // MARK: - Recent searches (UserDefaults)

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
