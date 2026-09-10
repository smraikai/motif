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
    init(tools: URL = Bundle.main.resourceURL!.appendingPathComponent("Tools"), cacheDirectory: URL? = nil) {
        self.tools = tools
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.itsdotdev.motif/yt-dlp", isDirectory: true)
    }
    var available: Bool {
        ["yt-dlp", "deno"].allSatisfy { FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent($0).path) }
    }
    @discardableResult
    func request(_ arguments: [String], completion: @escaping (Result<Data, Error>) -> Void) -> Extraction {
        let request = Extraction()
        request.run(executable: tools.appendingPathComponent("yt-dlp"), arguments: [
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
        request(["--no-playlist", "--skip-download", "--dump-single-json", "--format",
                 "bestaudio[ext=m4a]/bestaudio[protocol*=m3u8]/best[ext=mp4]", track.url.absoluteString]) {
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
