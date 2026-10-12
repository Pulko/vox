import Foundation

@MainActor
final class DownloadProgress: ObservableObject {
    @Published var fraction: Double = 0
    @Published var status: String = "Preparing…"
    @Published var errorMessage: String?
    @Published var isFinished = false

    func update(received: Int64, total: Int64, status: String) {
        self.status = status
        if total > 0 {
            fraction = min(1, Double(received) / Double(total))
        }
    }
}
