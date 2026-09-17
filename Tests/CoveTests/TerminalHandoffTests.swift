import XCTest
@testable import Cove

final class TerminalHandoffTests: XCTestCase {
    private let fakeAppURL = URL(fileURLWithPath: "/Applications/Fake Terminal.app")

    func testWeztermArguments() {
        let cwd = "/Users/mateus/Projetos com espaço"
        let result = TerminalApp.launchArguments(app: .wezterm, appURL: fakeAppURL, cwd: cwd)
        XCTAssertEqual(result.executable?.path, "/Applications/Fake Terminal.app/Contents/MacOS/wezterm")
        XCTAssertEqual(result.arguments, ["start", "--cwd", cwd])
    }

    func testKittyArguments() {
        let cwd = "/tmp/algum diretorio"
        let result = TerminalApp.launchArguments(app: .kitty, appURL: fakeAppURL, cwd: cwd)
        XCTAssertEqual(result.executable?.path, "/Applications/Fake Terminal.app/Contents/MacOS/kitty")
        XCTAssertEqual(result.arguments, ["--directory", cwd])
    }

    func testAlacrittyArguments() {
        let cwd = "/tmp/alacritty cwd"
        let result = TerminalApp.launchArguments(app: .alacritty, appURL: fakeAppURL, cwd: cwd)
        XCTAssertEqual(result.executable?.path, "/Applications/Fake Terminal.app/Contents/MacOS/alacritty")
        XCTAssertEqual(result.arguments, ["--working-directory", cwd])
    }

    func testITermUsesOpen() {
        let cwd = "/tmp/iterm cwd"
        let result = TerminalApp.launchArguments(app: .iterm, appURL: fakeAppURL, cwd: cwd)
        XCTAssertEqual(result.executable?.path, "/usr/bin/open")
        XCTAssertEqual(result.arguments, ["-a", fakeAppURL.path, cwd])
    }

    func testTerminalUsesOpen() {
        let cwd = "/tmp/terminal cwd"
        let result = TerminalApp.launchArguments(app: .terminal, appURL: fakeAppURL, cwd: cwd)
        XCTAssertEqual(result.executable?.path, "/usr/bin/open")
        XCTAssertEqual(result.arguments, ["-a", fakeAppURL.path, cwd])
    }

    /// Caminho com espaço preservado como um único argumento (nunca splitado).
    func testPathWithSpacesStaysOneArgument() {
        let cwd = "/Volumes/Disco Externo/pasta com espaço"
        let result = TerminalApp.launchArguments(app: .kitty, appURL: fakeAppURL, cwd: cwd)
        XCTAssertEqual(result.arguments.count, 2)
        XCTAssertEqual(result.arguments.last, cwd)
    }

    func testInstalledLookupNeverCrashesWhenAppMissing() {
        // Sem dependência de apps reais instalados no ambiente de CI: garante
        // que a busca via NSWorkspace não lança/trava E que o resultado é
        // sempre um subconjunto válido de TerminalApp.allCases (sem duplicata).
        for app in TerminalApp.allCases {
            _ = TerminalApp.launchArguments(app: app, cwd: NSHomeDirectory())
        }
        let installed = TerminalApp.installed()
        XCTAssertTrue(Set(installed).isSubset(of: Set(TerminalApp.allCases)))
        XCTAssertEqual(installed.count, Set(installed).count, "installed() não deve repetir apps")
    }

    func testLabelsAndBundleIDsAreNotEmpty() {
        for app in TerminalApp.allCases {
            XCTAssertFalse(app.label.isEmpty)
            XCTAssertFalse(app.bundleID.isEmpty)
        }
    }
}
