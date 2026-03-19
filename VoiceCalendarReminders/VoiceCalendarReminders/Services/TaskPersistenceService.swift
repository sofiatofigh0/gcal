import Foundation

final class TaskPersistenceService {
    static let shared = TaskPersistenceService()
    private let fileURL: URL

    private init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsDirectory.appendingPathComponent("voice_tasks.json")
    }

    func loadTasks() -> [VoiceTask] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([VoiceTask].self, from: data)
        } catch {
            return []
        }
    }

    func saveTasks(_ tasks: [VoiceTask]) {
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }
}
