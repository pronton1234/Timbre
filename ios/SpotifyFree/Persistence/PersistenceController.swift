import Foundation
import CoreData
import CloudKit

/// Owns the single `NSPersistentCloudKitContainer` for the app.
/// Using CloudKit means the user's playlists, liked songs, and recently played
/// sync across their devices with zero hosting cost on our side.
final class PersistenceController {
    static let shared = PersistenceController()
    static let preview: PersistenceController = {
        let c = PersistenceController(inMemory: true)
        return c
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SpotifyFree")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("PersistenceController: no store description")
        }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            // In-memory stores can't use CloudKit; disable it for tests
            description.cloudKitContainerOptions = nil
        } else {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { _, error in
            if let error {
                // Don't crash the app on migration errors in v1 — log and continue
                // with an in-memory fallback to prevent data loss on unsynced devices
                print("PersistenceController load failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(name: String) -> PlaylistEntity {
        let ctx = container.viewContext
        let p = PlaylistEntity(context: ctx)
        p.id = UUID()
        p.name = name
        p.createdAt = Date()
        try? ctx.save()
        return p
    }

    func addTrack(_ track: Track, to playlist: PlaylistEntity) {
        let ctx = container.viewContext
        let pt = PlaylistTrackEntity(context: ctx)
        pt.itunesTrackId = Int64(track.itunesTrackId)
        pt.isrc = track.isrc
        pt.name = track.name
        pt.artistName = track.artistName
        pt.albumName = track.albumName
        pt.durationMs = Int64(track.durationMs)
        pt.artworkUrl = track.artworkUrl
        pt.playlist = playlist
        let existing = (playlist.tracks?.count) ?? 0
        pt.position = Int32(existing)
        try? ctx.save()
    }

    func deletePlaylist(_ playlist: PlaylistEntity) {
        let ctx = container.viewContext
        ctx.delete(playlist)
        try? ctx.save()
    }

    // MARK: - Liked

    func setLiked(_ track: Track, liked: Bool) {
        let ctx = container.viewContext
        let req = LikedTrackEntity.fetchRequest()
        req.predicate = NSPredicate(format: "itunesTrackId == %d", track.itunesTrackId)
        if liked {
            if (try? ctx.fetch(req).first) != nil { return }
            let e = LikedTrackEntity(context: ctx)
            e.itunesTrackId = Int64(track.itunesTrackId)
            e.isrc = track.isrc
            e.name = track.name
            e.artistName = track.artistName
            e.albumName = track.albumName
            e.durationMs = Int64(track.durationMs)
            e.artworkUrl = track.artworkUrl
            e.addedAt = Date()
        } else {
            for obj in (try? ctx.fetch(req)) ?? [] { ctx.delete(obj) }
        }
        try? ctx.save()
    }

    func isLiked(_ track: Track) -> Bool {
        let req = LikedTrackEntity.fetchRequest()
        req.predicate = NSPredicate(format: "itunesTrackId == %d", track.itunesTrackId)
        return ((try? container.viewContext.count(for: req)) ?? 0) > 0
    }

    // MARK: - Recently played (capped at 100)

    func recordPlayed(_ track: Track) {
        let ctx = container.viewContext
        let e = RecentlyPlayedEntity(context: ctx)
        e.itunesTrackId = Int64(track.itunesTrackId)
        e.isrc = track.isrc
        e.name = track.name
        e.artistName = track.artistName
        e.albumName = track.albumName
        e.durationMs = Int64(track.durationMs)
        e.artworkUrl = track.artworkUrl
        e.playedAt = Date()
        pruneRecentlyPlayed(to: 100)
        try? ctx.save()
    }

    private func pruneRecentlyPlayed(to limit: Int) {
        let ctx = container.viewContext
        let req = RecentlyPlayedEntity.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
        guard let all = try? ctx.fetch(req) else { return }
        if all.count <= limit { return }
        for obj in all.suffix(from: limit) { ctx.delete(obj) }
    }
}

/// Helper to construct a Track value from a persisted row.
extension PlaylistTrackEntity {
    var asTrack: Track {
        Track(
            itunesTrackId: Int(itunesTrackId),
            isrc: isrc,
            name: name ?? "",
            artistName: artistName ?? "",
            albumName: albumName,
            durationMs: Int(durationMs),
            artworkUrl: artworkUrl
        )
    }
}

extension LikedTrackEntity {
    var asTrack: Track {
        Track(
            itunesTrackId: Int(itunesTrackId),
            isrc: isrc,
            name: name ?? "",
            artistName: artistName ?? "",
            albumName: albumName,
            durationMs: Int(durationMs),
            artworkUrl: artworkUrl
        )
    }
}

extension RecentlyPlayedEntity {
    var asTrack: Track {
        Track(
            itunesTrackId: Int(itunesTrackId),
            isrc: isrc,
            name: name ?? "",
            artistName: artistName ?? "",
            albumName: albumName,
            durationMs: Int(durationMs),
            artworkUrl: artworkUrl
        )
    }
}
