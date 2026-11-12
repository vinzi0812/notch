import Foundation
import Testing
@testable import Notch

@MainActor
struct TerminalSessionTests {
    @Test func shellRunsCommandsAndOutputSurvivesTabSwitch() async {
        // A bare shell: no login or dotfiles, so the test doesn't depend on anyone's setup.
        let session = TerminalSession(shell: "/bin/zsh", arguments: ["-f", "-i"])
        #expect(!session.isRunning, "the shell starts only when Terminal opens")

        var firstOutput = Data()
        let first = session.attachWebView { firstOutput.append($0) }
        session.start()
        #expect(session.isRunning)
        session.webViewDidBecomeReady(generation: first)
        session.sendData("printf '%s%s\\n' NOTCH_ TERMINAL_OK\n")
        #expect(await eventually(timeout: .seconds(10)) {
            String(decoding: firstOutput, as: UTF8.self).contains("NOTCH_TERMINAL_OK")
        })

        session.detachWebView(generation: first)
        var replayed = Data()
        let second = session.attachWebView { replayed.append($0) }
        session.webViewDidBecomeReady(generation: second)
        #expect(String(decoding: replayed, as: UTF8.self).contains("NOTCH_TERMINAL_OK"))

        session.sendData("exit\n")
        #expect(await eventually(timeout: .seconds(5)) { !session.isRunning })
        session.detachWebView(generation: second)
    }

    @Test func stoppingEndsTheShellAndForgetsItsOutput() async {
        let session = TerminalSession(shell: "/bin/zsh", arguments: ["-f", "-i"])
        var output = Data()
        let first = session.attachWebView { output.append($0) }
        session.start()
        session.webViewDidBecomeReady(generation: first)
        session.sendData("printf '%s%s\\n' STILL_ HERE\n")
        #expect(await eventually(timeout: .seconds(10)) {
            String(decoding: output, as: UTF8.self).contains("STILL_HERE")
        })

        session.hasSelection = true
        session.stop()
        #expect(!session.isRunning && !session.hasSelection)

        var replayed = Data()
        let second = session.attachWebView { replayed.append($0) }
        session.webViewDidBecomeReady(generation: second)
        #expect(replayed.isEmpty, "a stopped shell leaves nothing to replay")
    }
}
