import SwiftUI
import AVFoundation
import UIKit

@main
struct SpotifyFreeApp: App {
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var queue = QueueManager.shared
    @StateObject private var router = TabRouter()
    let persistence = PersistenceController.shared

    init() {
        FontLoader.registerBundledFonts()
        configureAudioSession()
        AppAppearance.configure()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppTheme.bg.ignoresSafeArea()
                RootShell()
            }
            .environmentObject(player)
            .environmentObject(queue)
            .environmentObject(router)
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .preferredColorScheme(.dark)
            .tint(.white)
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

/// ZStack shell: selected-tab content at the bottom of the stack, with the
/// MiniPlayer + custom tab bar overlaid. FullPlayer and Queue come up as
/// fullScreenCover modals.
struct RootShell: View {
    @EnvironmentObject var router: TabRouter
    @EnvironmentObject var queue: QueueManager
    @State private var showQueue = false
    @State private var showFullPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Selected tab content
            Group {
                switch router.selected {
                case .home:    HomeView()
                case .search:  SearchView()
                case .library: LibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MiniPlayer + tab bar stack
            VStack(spacing: 0) {
                if queue.currentIndex >= 0, queue.queue.indices.contains(queue.currentIndex) {
                    MiniPlayerCard(onTap: { showFullPlayer = true })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                SleekTabBar(selected: $router.selected, onQueueTap: { showQueue = true })
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(onDismiss: { showFullPlayer = false })
        }
        .fullScreenCover(isPresented: $showQueue) {
            QueueView(onDismiss: { showQueue = false })
        }
    }
}
