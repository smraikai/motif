import Foundation

@main struct CoreTests {
    static func main() throws {
        let fixture = """
        {"entries":[
          {"id":"abcdefghijk","title":"First song","channel":"Artist","duration":123},
          {"id":"abcdefghijk","title":"Duplicate"},
          {"id":"../invalid!","title":"Bad ID"},
          {"id":"lmnopqrstuv","title":"Live channel","live_status":"is_live","duration":null},
          {"id":"12345678901","title":"[Private video]"}
        ]}
        """
        let tracks = try Track.parse(Data(fixture.utf8))
        precondition(tracks.count == 2)
        precondition(tracks[0].durationLabel == "2:03")
        precondition(tracks[1].durationLabel == "LIVE")
        precondition(tracks[1].artist == "YouTube")
        var queue = QueueState(tracks: tracks, index: 0)
        precondition(queue.advance(by: 1, wrap: false))
        precondition(!queue.advance(by: 1, wrap: false))
        precondition(queue.index == 1)
        precondition(queue.advance(by: 1, wrap: true) && queue.index == 0)
        precondition(queue.advance(by: -1, wrap: true) && queue.index == 1)
        queue.appendUnique(tracks + tracks)
        precondition(queue.tracks.count == 2 && queue.current?.id == tracks[1].id)
        let saved = try JSONEncoder().encode(queue)
        let restored = try JSONDecoder().decode(QueueState.self, from: saved)
        precondition(restored.current == tracks[1])
        precondition(!QueueState(tracks: tracks, index: 99).isValid)
        var empty = QueueState()
        precondition(!empty.advance(by: 1, wrap: true))
        precondition(clockTime(.nan) == "0:00" && clockTime(3661) == "1:01:01")
        print("PASS: parsing, invalid IDs, deduplication, live tracks, queue boundaries, persistence, time formatting")
    }
}
