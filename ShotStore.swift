// ShotStore.swift
// GolfShotApp
//
// Persistent storage for shots using JSON files in the app's Documents directory.

import Foundation
import Combine

@MainActor
final class ShotStore: ObservableObject {

    static let shared = ShotStore()

    @Published private(set) var shots: [Shot] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("shots.json")
    }()

    private init() {
        load()
    }

    // MARK: - Public API

    func add(shot: Shot) {
        shots.insert(shot, at: 0)
        save()
    }

    func delete(shot: Shot) {
        shots.removeAll { $0.id == shot.id }
        // Remove associated video file if present
        if let filename = shot.videoFilename {
            let videoURL = videosDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: videoURL)
        }
        save()
    }

    func shots(for club: Club) -> [Shot] {
        shots.filter { $0.club == club }
    }

    // MARK: - Videos directory

    var videosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(shots)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            print("ShotStore: failed to save – \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            shots = try JSONDecoder().decode([Shot].self, from: data)
        } catch {
            print("ShotStore: failed to load – \(error)")
        }
    }
}
