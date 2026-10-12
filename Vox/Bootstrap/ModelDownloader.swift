import Foundation

struct HuggingFaceFile: Sendable {
    let path: String
    let size: Int64
}

actor ModelDownloader {
    private let store: ModelStore
    private let session: URLSession
    private let progress: DownloadProgress

    init(store: ModelStore, progress: DownloadProgress, session: URLSession = .shared) {
        self.store = store
        self.progress = progress
        self.session = session
    }

    func downloadAll() async throws {
        if let llm = VoxPreferences.selectedLLM, !store.isReady(llm) {
            try await downloadRepo(
                llm.repo,
                prefix: nil,
                destination: store.directory(for: llm),
                label: llm.title
            )
        }
        if !store.whisperReady {
            try await downloadRepo(
                ModelStore.whisperRepo,
                prefix: ModelStore.whisperPrefix,
                destination: store.whisperDirectory,
                label: "Whisper base"
            )
        }
        await MainActor.run {
            progress.fraction = 1
            progress.status = "Models ready"
            progress.isFinished = true
        }
    }

    private func downloadRepo(
        _ repo: String,
        prefix: String?,
        destination: URL,
        label: String
    ) async throws {
        await MainActor.run { progress.status = "Listing \(label) files…" }
        var files = try await listFiles(repo: repo)
        if let prefix {
            let root = prefix.hasSuffix("/") ? prefix : prefix + "/"
            files = files.filter { $0.path == prefix || $0.path.hasPrefix(root) }
        }
        files = files.filter { !$0.path.hasSuffix(".complete") }

        let total = max(1, files.reduce(Int64(0)) { $0 + max($1.size, 1) })
        var received: Int64 = 0

        try store.prepareDirectory(destination)

        for file in files {
            let relative: String
            if let prefix {
                if file.path == prefix {
                    continue
                }
                let root = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                relative = String(file.path.dropFirst(root.count + 1))
            } else {
                relative = file.path
            }
            guard !relative.isEmpty else { continue }

            await MainActor.run {
                progress.update(
                    received: received,
                    total: total,
                    status: "Downloading \(label): \(relative)"
                )
            }

            let dest = destination.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await downloadFile(repo: repo, path: file.path, to: dest)
            received += max(file.size, 1)
            await MainActor.run {
                progress.update(received: received, total: total, status: "Downloading \(label): \(relative)")
            }
        }

        try store.markComplete(destination)
        Log.download.info("Finished \(label, privacy: .public)")
    }

    private func listFiles(repo: String) async throws -> [HuggingFaceFile] {
        var results: [HuggingFaceFile] = []
        var next: URL? = URL(
            string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=1"
        )

        while let url = next {
            var request = URLRequest(url: url)
            request.setValue("Vox/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw VoxError.downloadFailed("list \(repo) failed (\(code))")
            }
            let items = try JSONDecoder().decode([TreeItem].self, from: data)
            for item in items where item.type == "file" {
                results.append(HuggingFaceFile(path: item.path, size: item.byteSize))
            }
            next = Self.nextURL(from: http.value(forHTTPHeaderField: "Link"))
        }
        return results
    }

    private func downloadFile(repo: String, path: String, to destination: URL) async throws {
        let encodedPath = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encodedPath)") else {
            throw VoxError.downloadFailed("bad URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue("Vox/1.0", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VoxError.downloadFailed("\(path) (\(code))")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    private static func nextURL(from linkHeader: String?) -> URL? {
        guard let linkHeader else { return nil }
        for part in linkHeader.split(separator: ",") {
            let bits = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard bits.count >= 2, bits[1].contains("rel=\"next\"") else { continue }
            let urlPart = bits[0]
            guard urlPart.hasPrefix("<"), urlPart.hasSuffix(">") else { continue }
            return URL(string: String(urlPart.dropFirst().dropLast()))
        }
        return nil
    }
}

private struct TreeItem: Decodable {
    let type: String
    let path: String
    let size: Int64?
    let lfs: LFS?

    struct LFS: Decodable {
        let size: Int64?
    }

    var byteSize: Int64 {
        lfs?.size ?? size ?? 0
    }
}
