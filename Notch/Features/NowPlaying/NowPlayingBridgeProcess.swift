import Foundation

/// Runs the NowPlayingBridge library inside Apple's /usr/bin/perl and talks to it over pipes:
/// JSON lines come out of its stdout, commands go into its stdin.
final class NowPlayingBridgeProcess {
    enum Command: String {
        case toggle, next, previous
    }

    /// A new snapshot; nil for a line that couldn't be read (e.g. the bridge reporting an error).
    var onUpdate: ((NowPlayingSnapshot?) -> Void)?
    var onExit: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?

    static let defaultLibraryURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("libNowPlayingBridge.dylib")

    var isRunning: Bool { process?.isRunning == true }

    func start(libraryURL: URL) throws {
        stop()

        let perl = Process()
        perl.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        perl.arguments = ["-e", "use DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();", libraryURL.path]
        perl.environment = ["NOTCH_NOW_PLAYING_BRIDGE": "1"]

        let output = Pipe()
        let commands = Pipe()
        perl.standardOutput = output
        perl.standardInput = commands
        perl.standardError = FileHandle.nullDevice
        perl.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.onExit?() }
        }

        try perl.run()
        process = perl
        input = commands.fileHandleForWriting

        let reader = output.fileHandleForReading
        self.output = reader
        var buffer = LineBuffer()
        // Called on a background queue whenever the pipe has data; an empty read means the bridge exited.
        reader.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let updates = buffer.append(chunk).map { try? NowPlayingSnapshot.decode(line: $0) }
            Task { @MainActor in
                for update in updates { self?.onUpdate?(update) }
            }
        }
    }

    func send(_ command: Command) {
        try? input?.write(contentsOf: Data((command.rawValue + "\n").utf8))
    }

    /// Seeks the system player to the given position in seconds.
    func sendSeek(to position: TimeInterval) {
        try? input?.write(contentsOf: Data("seek \(position)\n".utf8))
    }

    /// Closing stdin tells the bridge to exit; terminate() covers the case where it doesn't.
    func stop() {
        output?.readabilityHandler = nil
        output = nil
        try? input?.close()
        input = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }
}
