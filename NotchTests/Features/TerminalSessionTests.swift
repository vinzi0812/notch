import Foundation
import Testing
@testable import Notch

@MainActor
struct TerminalSessionTests {
    @Test func shellRunsCommandsAndOutputSurvivesTabSwitch() async {
        let session = TerminalSession()
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
}
