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
    @Environment(\.textEditing) private var textEditing

    var body: some View {
        VStack(spacing: 0) {
            // ── Full-width Title Bar ──────────────────────────────────────
            HStack(spacing: 0) {
                // Left: terminal icon + shell label
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(session.shellName)
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
                            .foregroundStyle(copied ? .green : .white.opacity(session.hasSelection ? 0.5 : 0.2))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.hasSelection && !copied)
                    .help(session.hasSelection ? "Copy Selection" : "Select text to copy it")

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
            TerminalWebView(session: session, fontSize: fontSize, webViewRef: $webViewRef) { focused in
                textEditing(focused)   // typing in the terminal keeps the notch open, as in Notes
            }
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
            if !session.isRunning { session.start() }
        }
        .onDisappear { textEditing(false) }
    }
}

// MARK: - FocusableWKWebView

/// Takes the keyboard only when clicked, like a note. It never activates the app: the notch is a
/// non-activating panel, so the app you were using stays the active one while you type here.
final class FocusableWKWebView: WKWebView {
    var onFocusChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeKey()
        window?.makeFirstResponder(self)
        evaluateJavaScript("term.focus();", completionHandler: nil)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChange?(false)
            evaluateJavaScript("term.blur();", completionHandler: nil)
        }
        return resigned
    }
}

// MARK: - TerminalWebView

struct TerminalWebView: NSViewRepresentable {
    let session: TerminalSession
    let fontSize: Double
    @Binding var webViewRef: WKWebView?
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "terminal")
        let webView = FocusableWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background

        webView.onFocusChange = onFocusChange

        // Xcode flattens synchronized-folder resources into Resources; look in both places.
        if let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html", subdirectory: "xterm")
            ?? Bundle.main.url(forResource: "terminal", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

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
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }

            if type == "ready" {
                session.webViewDidBecomeReady(generation: generation)
            } else if type == "data", let str = dict["data"] as? String {
                session.sendData(str)
            } else if type == "selection", let has = dict["hasSelection"] as? Bool {
                session.hasSelection = has
            } else if type == "resize", let cols = dict["cols"] as? Int, let rows = dict["rows"] as? Int {
                session.resize(cols: cols, rows: rows)
            }
        }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var terminalFontSize: Double = 11
}
