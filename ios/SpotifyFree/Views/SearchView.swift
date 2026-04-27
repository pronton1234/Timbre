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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    Text("Search")
                        .font(.display(40))
                        .foregroundStyle(Color.mmForeground)
                        .padding(.bottom, 24)

                    // Search box
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
                            Button { term = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.mmMutedFg)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.mmMuted.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.bottom, 32)

                    // Content
                    let trimmed = term.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        if recentSearches.isEmpty {
                            Text("Search for any song, artist, or album.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.mmMutedFg)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 64)
                        } else {
                            recentsSection
                        }
                    } else if tracks.isEmpty && albums.isEmpty && artists.isEmpty {
                        Text("No results for \"\(trimmed)\"")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mmMutedFg)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 64)
                    } else {
                        resultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 160)
            }
            .background(Color.clear)
            .navigationBarHidden(true)
            .onChange(of: term) { _ in debounceSearch() }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        }
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
    }

    // MARK: - Recents

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(recentSearches, id: \.self) { q in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.mmSurface)
                        Image(systemName: "clock")
                            .foregroundStyle(Color.mmMutedFg)
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
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !tracks.isEmpty {
                sectionBlock(title: "Songs") {
                    VStack(spacing: 4) {
                        ForEach(tracks) { t in
                            TrackRow(
                                track: t,
                                onTap: {
                                    recordRecent(term)
                                    Task { await queue.playNow([t]) }
                                },
                                onAddToQueue: { queue.addToQueue(t) }
                            )
                        }
                    }
                }
            }
            if !albums.isEmpty {
                sectionBlock(title: "Albums") {
                    VStack(spacing: 4) {
                        ForEach(albums) { a in
                            NavigationLink(value: a) { albumRow(a) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !artists.isEmpty {
                sectionBlock(title: "Artists") {
                    VStack(spacing: 4) {
                        ForEach(artists) { ar in
                            NavigationLink(value: ar) { artistRow(ar) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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
            async let t  = (try? await iTunesClient.shared.searchTracks(q))  ?? []
            async let al = (try? await iTunesClient.shared.searchAlbums(q))  ?? []
            async let ar = (try? await iTunesClient.shared.searchArtists(q)) ?? []
            let (tv, av, arv) = await (t, al, ar)
            await MainActor.run { tracks = tv; albums = av; artists = arv }
        }
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
