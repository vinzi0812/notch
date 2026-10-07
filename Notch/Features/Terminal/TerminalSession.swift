import AppKit
import Foundation

/// A persistent shell session running in the background.
/// The process stays alive across tab switches; only terminates when the app quits
/// or the user explicitly resets it.
@Observable
final class TerminalSession {

    // MARK: - Published state
    private(set) var isRunning = false

    // Callbacks for the UI
    @ObservationIgnored private var onDataReceived: ((Data) -> Void)?
    @ObservationIgnored private var outputHistory = Data()
    @ObservationIgnored private var isWebReady = false
    @ObservationIgnored private var webViewGeneration = 0

    func attachWebView(onDataReceived: @escaping (Data) -> Void) -> Int {
        webViewGeneration += 1
        isWebReady = false
        self.onDataReceived = onDataReceived
        return webViewGeneration
    }

    func detachWebView(generation: Int) {
        guard generation == webViewGeneration else { return }
        isWebReady = false
        onDataReceived = nil
    }

    func webViewDidBecomeReady(generation: Int) {
        guard generation == webViewGeneration else { return }
        isWebReady = true
        if !outputHistory.isEmpty {
            onDataReceived?(outputHistory)
        }
        // Kick the shell with SIGWINCH so it redraws the prompt at the correct size.
        // This is needed because p10k / zsh draw the prompt on startup before the
        // web view exists; the buffer flush above replays that output, but sending
        // SIGWINCH forces a fresh prompt repaint once xterm.js is actually visible.
        let pid = process?.processIdentifier ?? 0
        if pid > 0 {
            kill(pid, SIGWINCH)
            // Send a second kick after fit() has had time to run and send the real cols/rows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, let pid = self.process?.processIdentifier, pid > 0 else { return }
                kill(pid, SIGWINCH)
            }
        }
    }

    // MARK: - Private
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var masterHandle: FileHandle?
    @ObservationIgnored private var masterFD: Int32 = -1

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        outputHistory = Data()
        // A restarted shell reuses the already loaded web view.

        var master: Int32 = 0
        var slave: Int32 = 0
        var win = winsize(ws_row: 30, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        if openpty(&master, &slave, nil, nil, &win) == -1 {
            print("Failed to openpty")
            return
        }

        let mHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let sHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-i", "-l"]
        p.standardInput = sHandle
        p.standardOutput = sHandle
        p.standardError = sHandle

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        p.environment = env

        p.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                guard let self, self.process === terminated else { return }
                self.isRunning = false
            }
        }

        do {
            try p.run()
        } catch {
            print("Failed to start shell: \(error)")
            return
        }

        sHandle.closeFile()

        process = p
        masterHandle = mHandle
        masterFD = master
        isRunning = true

        mHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.outputHistory.append(data)
                if self.outputHistory.count > 2_000_000 {
                    self.outputHistory = Data(self.outputHistory.suffix(2_000_000))
                }
                if self.isWebReady, let callback = self.onDataReceived {
                    callback(data)
                }
            }
        }
    }

    func sendData(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        try? masterHandle?.write(contentsOf: data)
    }

    func resize(cols: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var winsz = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, UInt(TIOCSWINSZ), &winsz)
        // Signal the shell to re-query terminal size and redraw
        if let pid = process?.processIdentifier, pid > 0 {
            kill(pid, SIGWINCH)
        }
    }

    func reset() {
        outputHistory = Data()
        masterHandle?.readabilityHandler = nil
        process?.terminate()
        process = nil
        masterHandle = nil
        masterFD = -1
        isRunning = false
        start()
    }

}
