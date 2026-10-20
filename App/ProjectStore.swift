import Foundation
import Observation
import RoomGeometry
import RoomPlan

struct Project: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var room: Room?
    var overrides: MeasurementOverrides
    var notes: String

    var measurements: RoomMeasurements? {
        room.map { MeasurementCalculator.measure($0, overrides: overrides) }
    }
}

/// Stores each project in its own folder under Documents/Projects:
///
///     <id>/project.json        metadata, converted geometry, manual overrides
///     <id>/captured-room.json  RoomPlan's raw CapturedRoom, kept for reprocessing
///     <id>/model.usdz          parametric 3D model
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    var lastError: String?

    private let root: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(root: URL = URL.documentsDirectory.appending(path: "Projects", directoryHint: .isDirectory)) {
        self.root = root
        load()
    }

    func project(_ id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    func directory(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func modelURL(for id: UUID) -> URL? {
        let url = directory(for: id).appending(path: "model.usdz")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func create(name: String) -> Project {
        let now = Date()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(
            id: UUID(),
            name: trimmed.isEmpty ? "Untitled room" : trimmed,
            createdAt: now,
            updatedAt: now,
            room: nil,
            overrides: MeasurementOverrides(),
            notes: ""
        )
        update(project)
        return project
    }

    func update(_ project: Project) {
        var project = project
        project.updatedAt = Date()
        do {
            let dir = directory(for: project.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(project).write(to: dir.appending(path: "project.json"), options: .atomic)
        } catch {
            lastError = "Could not save \(project.name): \(error.localizedDescription)"
            return
        }
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
    }

    /// Replaces the project's scan. Manual overrides are cleared because they refer to the old walls.
    func attachScan(_ captured: CapturedRoom, to id: UUID) {
        guard var project = project(id) else { return }
        let dir = directory(for: id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(captured).write(to: dir.appending(path: "captured-room.json"), options: .atomic)
            let modelURL = dir.appending(path: "model.usdz")
            try? FileManager.default.removeItem(at: modelURL)
            try captured.export(to: modelURL, exportOptions: .parametric)
        } catch {
            lastError = "The scan was kept, but saving its files failed: \(error.localizedDescription)"
        }
        project.room = RoomConverter.room(from: captured)
        project.overrides = MeasurementOverrides()
        update(project)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
        projects.removeAll { $0.id == id }
    }

    private func load() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        projects = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "project.json")) else { return nil }
            return try? decoder.decode(Project.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }
}
