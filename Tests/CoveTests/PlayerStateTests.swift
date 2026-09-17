import XCTest
@testable import Cove

final class PlayerStateTests: XCTestCase {
    func testShuffleSymbol() {
        XCTAssertEqual(PlayerState.symbol(for: .shuffle(false)).name, "shuffle")
        XCTAssertFalse(PlayerState.symbol(for: .shuffle(false)).tinted)
        XCTAssertEqual(PlayerState.symbol(for: .shuffle(true)).name, "shuffle")
        XCTAssertTrue(PlayerState.symbol(for: .shuffle(true)).tinted)
    }

    func testRepeatSymbol() {
        let off = PlayerState.symbol(for: .repeatMode(.off))
        XCTAssertEqual(off.name, "repeat")
        XCTAssertFalse(off.tinted)

        let all = PlayerState.symbol(for: .repeatMode(.all))
        XCTAssertEqual(all.name, "repeat")
        XCTAssertTrue(all.tinted)

        let one = PlayerState.symbol(for: .repeatMode(.one))
        XCTAssertEqual(one.name, "repeat.1")
        XCTAssertTrue(one.tinted)
    }

    func testFavoriteSymbol() {
        XCTAssertEqual(PlayerState.symbol(for: .favorite(nil)).name, "heart")
        XCTAssertFalse(PlayerState.symbol(for: .favorite(nil)).tinted)
        XCTAssertEqual(PlayerState.symbol(for: .favorite(false)).name, "heart")
        XCTAssertFalse(PlayerState.symbol(for: .favorite(false)).tinted)
        XCTAssertEqual(PlayerState.symbol(for: .favorite(true)).name, "heart.fill")
        XCTAssertTrue(PlayerState.symbol(for: .favorite(true)).tinted)
    }

    func testChoosePlayerNoneRunning() {
        XCTAssertNil(PlayerBridge.choosePlayer(running: [], nowPlayingTitle: nil, titles: [:], playing: [:]))
    }

    func testChoosePlayerSingleRunning() {
        XCTAssertEqual(
            PlayerBridge.choosePlayer(running: [.spotify], nowPlayingTitle: nil, titles: [:], playing: [:]),
            .spotify
        )
    }

    func testChoosePlayerTitleMatchWins() {
        let chosen = PlayerBridge.choosePlayer(
            running: [.music, .spotify],
            nowPlayingTitle: "Faixa Spotify",
            titles: [.music: "Faixa Music", .spotify: "Faixa Spotify"],
            playing: [.music: true, .spotify: false]
        )
        XCTAssertEqual(chosen, .spotify)
    }

    func testChoosePlayerPlayingWinsOverIdleWhenNoTitleMatch() {
        let chosen = PlayerBridge.choosePlayer(
            running: [.music, .spotify],
            nowPlayingTitle: "Faixa desconhecida",
            titles: [.music: "Faixa Music", .spotify: "Faixa Spotify"],
            playing: [.music: false, .spotify: true]
        )
        XCTAssertEqual(chosen, .spotify)
    }

    func testChoosePlayerFallsBackToMusic() {
        let chosen = PlayerBridge.choosePlayer(
            running: [.music, .spotify],
            nowPlayingTitle: nil,
            titles: [.music: nil, .spotify: nil],
            playing: [.music: false, .spotify: false]
        )
        XCTAssertEqual(chosen, .music)
    }
}
