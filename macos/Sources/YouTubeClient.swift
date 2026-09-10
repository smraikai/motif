import Foundation

struct PlayerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// File output avoids filling a pipe while yt-dlp writes a large playlist.
// Each request owns its Process; cancelling never signals an unrelated PID.
final class Extraction {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private let onCancel: (() -> Void)?
    init(onCancel: (() -> Void)? = nil) { self.onCancel = onCancel }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
        onCancel?()
    }
    func run(executable: URL, arguments: [String], completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let output = directory.appendingPathComponent("output.json")
                let errors = directory.appendingPathComponent("error.txt")
                FileManager.default.createFile(atPath: output.path, contents: nil)
                FileManager.default.createFile(atPath: errors.path, contents: nil)
                let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: errors)
                defer { try? out.close(); try? err.close() }
                let task = Process()
                task.executableURL = executable
                task.arguments = arguments
                task.standardOutput = out
                task.standardError = err
                task.standardInput = FileHandle.nullDevice
                self.lock.lock()
                if self.cancelled { self.lock.unlock(); return }
                self.process = task
                do { try task.run() } catch { self.lock.unlock(); throw error }
                self.lock.unlock()
                // Bound a stalled extractor, even if the network never responds.
                let timeout = DispatchWorkItem { self.cancel() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 65, execute: timeout)
                task.waitUntilExit()
                timeout.cancel()
                self.lock.lock(); let cancelled = self.cancelled; self.process = nil; self.lock.unlock()
                guard !cancelled else {
                    DispatchQueue.main.async { completion(.failure(PlayerError(message: "Request cancelled or timed out. Try again."))) }
                    return
                }
                let data = try Data(contentsOf: output)
                if task.terminationStatus != 0 {
                    let detail = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
                    let message = detail.split(separator: "\n").last.map(String.init) ?? "YouTube could not load this request. Try again."
                    throw PlayerError(message: String(message.prefix(350)))
                }
                DispatchQueue.main.async { completion(.success(data)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

protocol MusicClient {
    var available: Bool { get }
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction
}

final class YouTubeClient: MusicClient {
    let tools: URL
    let cacheDirectory: URL
    private let fastResolver: FastStreamResolver?
    var streamEvent: ((String, String) -> Void)?
    var extractor: URL {
        let unpacked = tools.appendingPathComponent("yt-dlp-runtime/yt-dlp_macos")
        return FileManager.default.isExecutableFile(atPath: unpacked.path) ? unpacked : tools.appendingPathComponent("yt-dlp")
    }
    init(tools: URL = Bundle.main.resourceURL!.appendingPathComponent("Tools"), cacheDirectory: URL? = nil, enableFastResolver: Bool = true, fastResolver: FastStreamResolver? = nil) {
        self.fastResolver = enableFastResolver ? (fastResolver ?? FastStreamResolver()) : nil
        self.fastResolver?.prepare()
        self.tools = tools
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.itsdotdev.motif/yt-dlp", isDirectory: true)
    }
    var available: Bool {
        FileManager.default.isExecutableFile(atPath: extractor.path) &&
            FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent("deno").path)
    }
    @discardableResult
    func request(_ arguments: [String], completion: @escaping (Result<Data, Error>) -> Void) -> Extraction {
        let request = Extraction()
        request.run(executable: extractor, arguments: [
            "--ignore-config", "--no-plugin-dirs", "--cache-dir", cacheDirectory.path, "--no-warnings",
            "--socket-timeout", "15", "--retries", "1", "--extractor-retries", "1",
            "--js-runtimes", "deno:\(tools.appendingPathComponent("deno").path)"
        ] + arguments, completion: completion)
        return request
    }
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        request(["--flat-playlist", "--skip-download", "--dump-single-json", "ytsearch12:\(query)"]) {
            completion($0.flatMap { data in Result { try Track.parse(data) } })
        }
    }
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        request(["--flat-playlist", "--skip-download", "--playlist-end", "40", "--dump-single-json",
                 "https://www.youtube.com/watch?v=\(seed.id)&list=RDAMVM\(seed.id)"]) {
            completion($0.flatMap { data in Result { try Track.parse(data) } })
        }
    }
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction {
        guard let fastResolver, !track.isLive else { return fallbackStream(track, completion: completion) }
        var task: Task<Void, Never>?
        var fallback: Extraction?
        let token = Extraction {
            task?.cancel()
            DispatchQueue.main.async { fallback?.cancel() }
        }
        streamEvent?(track.id, "native-start")
        task = Task { @MainActor [weak self] in
            defer { task = nil }
            do {
                let url = try await fastResolver.stream(track)
                if !token.isCancelled {
                    self?.streamEvent?(track.id, "native-ready")
                    completion(.success(url))
                }
            } catch {
                guard !token.isCancelled, let self else { return }
                let detail = error is PlayerError ? error.localizedDescription : "\((error as NSError).domain):\((error as NSError).code)"
                self.streamEvent?(track.id, "native-failed: " + detail)
                fallback = self.fallbackStream(track) { result in
                    if !token.isCancelled { completion(result) }
                }
            }
        }
        return token
    }
    private func fallbackStream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction {
        streamEvent?(track.id, "extractor-start")
        // Prefer segmented audio. Some direct fragmented M4A streams never
        // become ready in AVPlayer, despite returning valid HTTP byte ranges.
        return request(["--no-playlist", "--skip-download", "--dump-single-json", "--format",
                 "bestaudio[protocol*=m3u8]/bestaudio[ext=m4a]/best[ext=mp4]", track.url.absoluteString]) {
            completion($0.flatMap { data in Result {
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let raw = object?["url"] as? String, let url = URL(string: raw), url.scheme == "https" else {
                    throw PlayerError(message: "YouTube did not return an audio stream this Mac can play.")
                }
                return url
            } })
        }
    }
}
