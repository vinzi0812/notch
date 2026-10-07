import SwiftUI

extension TerminalSession: NotchModule {
    var feature: NotchFeature { .terminal }
    var earPriority: Int? { nil }
    var tab: NotchTab? { NotchTab(title: "Terminal", symbol: "terminal", style: .tab) }
    var wantsTallPage: Bool { true }

    @ViewBuilder
    func content(for placement: NotchPlacement) -> some View {
        if placement == .page {
            TerminalPage(session: self)
        }
    }
}

// MARK: - Page
import WebKit

struct TerminalPage: View {
    let session: TerminalSession
    @Environment(\.terminalFontSize) private var fontSize
    @State private var webViewRef: WKWebView?
    @State private var copied: Bool = false

    // Derive a friendly shell name from the SHELL env var
    private var shellName: String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return URL(fileURLWithPath: shell).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Full-width Title Bar ──────────────────────────────────────
            HStack(spacing: 0) {
                // Left: terminal icon + shell label
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(shellName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.leading, 12)

                Spacer()

                // Right: action buttons
                HStack(spacing: 2) {
                    Button {
                        webViewRef?.evaluateJavaScript("term.getSelection()") { result, _ in
                            if let text = result as? String, !text.isEmpty {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                withAnimation(.snappy) { copied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation(.snappy) { copied = false }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(copied ? .green : .white.opacity(0.5))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("Copy Selection")

                    Button {
                        webViewRef?.evaluateJavaScript("clearTerminal()", completionHandler: nil)
                    } label: {
                        Image(systemName: "eraser")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("Clear Screen")

                    Button {
                        webViewRef?.evaluateJavaScript("clearTerminal()", completionHandler: nil)
                        session.reset()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("Restart Session")
                }
                .padding(.trailing, 8)
            }
            .frame(height: 28)
            .background(Color.white.opacity(0.04))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(Color.white.opacity(0.1)),
                alignment: .bottom
            )

            // ── Terminal WebView ──────────────────────────────────────────
            TerminalWebView(session: session, fontSize: fontSize, webViewRef: $webViewRef)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            if !session.isRunning { session.start() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let wv = webViewRef as? FocusableWKWebView { wv.focusTerminal() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let wv = webViewRef as? FocusableWKWebView { wv.focusTerminal() }
            }
        }
    }
}

// MARK: - FocusableWKWebView

final class FocusableWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func focusTerminal() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        evaluateJavaScript("term.focus(); doFit();", completionHandler: nil)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focusTerminal()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.focusTerminal()
            }
        }
    }
}

// MARK: - TerminalWebView

struct TerminalWebView: NSViewRepresentable {
    let session: TerminalSession
    let fontSize: Double
    @Binding var webViewRef: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "terminal")
        let webView = FocusableWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background

        // Xcode may flatten synchronized-folder resources into Resources.
        // Read the shipped HTML directly; never modify a signed app bundle.
        let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html", subdirectory: "xterm")
            ?? Bundle.main.url(forResource: "terminal", withExtension: "html")
            ?? URL(fileURLWithPath: #file).deletingLastPathComponent()
                .appendingPathComponent("xterm/terminal.html")
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())

        context.coordinator.webView = webView
        context.coordinator.fontSize = fontSize
        DispatchQueue.main.async { self.webViewRef = webView }

        context.coordinator.generation = session.attachWebView { data in
            let base64 = data.base64EncodedString()
            DispatchQueue.main.async {
                webView.evaluateJavaScript("writeData('\(base64)')", completionHandler: nil)
            }
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.fontSize = fontSize
        guard !webView.isLoading else { return }
        webView.evaluateJavaScript("term.options.fontSize = \(fontSize); doFit();", completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.session.detachWebView(generation: coordinator.generation)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "terminal")
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let session: TerminalSession
        var generation = 0
        var fontSize: Double = 11
        weak var webView: WKWebView?

        init(session: TerminalSession) {
            self.session = session
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("term.options.fontSize = \(fontSize); doFit();", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak webView] in
                guard let webView = webView as? FocusableWKWebView else { return }
                webView.focusTerminal()
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }

            if type == "ready" {
                session.webViewDidBecomeReady(generation: generation)
            } else if type == "data", let str = dict["data"] as? String {
                session.sendData(str)
            } else if type == "resize", let cols = dict["cols"] as? Int, let rows = dict["rows"] as? Int {
                session.resize(cols: cols, rows: rows)
            }
        }
    }
}

// MARK: - Environment key for font size

struct TerminalFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 11
}

extension EnvironmentValues {
    var terminalFontSize: CGFloat {
        get { self[TerminalFontSizeKey.self] }
        set { self[TerminalFontSizeKey.self] = newValue }
    }
}

// MARK: - Pointer Cursor Extension

extension View {
    func pointingHandCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
