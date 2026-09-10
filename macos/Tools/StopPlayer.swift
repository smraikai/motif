import AppKit

let identifiers = ["io.github.itsdotdev.motif", "io.github.itsdotdev.youtube-music.macos"]
let players = identifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
for player in players where !player.isTerminated {
    guard player.terminate() else {
        fputs("Quit \(player.localizedName ?? "the player") before installing Motif.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(10)
while players.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard players.allSatisfy({ $0.isTerminated }) else {
    fputs("The player is still running. Quit it before installing Motif.\n", stderr)
    exit(1)
}
