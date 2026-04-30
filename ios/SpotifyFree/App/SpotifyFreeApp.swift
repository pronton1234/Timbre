import SwiftUI
import AVFoundation
import UIKit

@main
struct SpotifyFreeApp: App {
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var queue = QueueManager.shared
    @StateObject private var router = TabRouter()
    @Environment(\.scenePhase) private var scenePhase
    let persistence = PersistenceController.shared

    init() {
        FontLoader.registerBundledFonts()
        configureAudioSession()
        AppAppearance.configure()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environmentObject(player)
                .environmentObject(queue)
                .environmentObject(router)
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .preferredColorScheme(.dark)
                .tint(Color.mmForeground)
                .onAppear {
                    // After queue is restored from disk, seek to saved position.
                    // Player stays paused — user resumes intentionally.
                    AudioPlayer.shared.restorePosition()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .inactive || phase == .background {
                AudioPlayer.shared.savePositionNow()
            }
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("AudioSession configure failed: \(error)")
        }
    }
}

struct RootShell: View {
    @EnvironmentObject var router: TabRouter
    @EnvironmentObject var queue: QueueManager
    @State private var showFullPlayer = false

    var body: some View {
        ZStack {
            stageGradient.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                // Tab content
                Group {
                    switch router.selected {
                    case .home:    HomeView()
                    case .search:  SearchView()
                    case .library: LibraryView()
                    case .queue:   QueueView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // MiniPlayer + TabBar
                VStack(spacing: 0) {
                    if queue.currentTrack != nil {
                        MiniPlayerCard(onTap: { showFullPlayer = true })
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                    SleekTabBar(selected: $router.selected)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            // NavigationStack so that artist-name taps can push ArtistDetailView.
            NavigationStack {
                FullPlayerView(onDismiss: { showFullPlayer = false })
                    .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
            }
        }
    }
}
