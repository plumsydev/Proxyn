import SwiftUI
import WebKit

enum ConsoleTarget: Hashable {
    case guest(GuestRef)
    case node(String)
}

/// Proxmox's own noVNC / xterm.js console in a web view, authenticated with the
/// session ticket. This gives a real framebuffer and shell without
/// reimplementing the VNC protocol.
struct ConsoleView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: ConsoleTarget
    let title: String

    @State private var session: PVESession?
    @State private var errorMessage: String?
    @State private var loading = true
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let session, let url = consoleURL, let profile = app.selectedServer {
                    ConsoleWebView(url: url, ticket: session.ticket, profile: profile, isLoading: $loading)
                        .id(reloadToken)
                        .ignoresSafeArea(edges: .bottom)
                }

                if let errorMessage {
                    ContentUnavailableView {
                        Label("Console Unavailable", systemImage: "apple.terminal")
                    } description: {
                        Text(errorMessage)
                    }
                    .foregroundStyle(.white)
                } else if loading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        loading = true
                        reloadToken = UUID()
                    }
                    .disabled(session == nil)
                }
            }
        }
        .task { await prepare() }
    }

    private var consoleURL: URL? {
        guard let base = app.selectedServer?.baseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }

        switch target {
        case .guest(let ref) where ref.kind == .qemu:
            components.queryItems = [
                .init(name: "console", value: "kvm"), .init(name: "novnc", value: "1"),
                .init(name: "vmid", value: String(ref.vmid)), .init(name: "node", value: ref.node),
                .init(name: "resize", value: "scale")
            ]
        case .guest(let ref):
            components.queryItems = [
                .init(name: "console", value: "lxc"), .init(name: "xtermjs", value: "1"),
                .init(name: "vmid", value: String(ref.vmid)), .init(name: "node", value: ref.node)
            ]
        case .node(let node):
            components.queryItems = [
                .init(name: "console", value: "shell"), .init(name: "xtermjs", value: "1"),
                .init(name: "node", value: node)
            ]
        }
        return components.url
    }

    private func prepare() async {
        guard let client = app.client() else {
            errorMessage = "No server is selected."
            return
        }
        do {
            session = try await client.consoleCredentials()
        } catch {
            errorMessage = (error as? ProxmoxError)?.localizedDescription ?? error.localizedDescription
            loading = false
        }
    }
}

private struct ConsoleWebView: UIViewRepresentable {
    let url: URL
    let ticket: String
    let profile: ServerProfile
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(profile: profile, isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false

        let cookie = HTTPCookie(properties: [
            .domain: profile.host,
            .path: "/",
            .name: "PVEAuthCookie",
            .value: ticket,
            .secure: profile.useHTTPS ? "TRUE" : "FALSE"
        ])
        if let cookie {
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                webView.load(URLRequest(url: url))
            }
        } else {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let profile: ServerProfile
        @Binding private var isLoading: Bool

        init(profile: ServerProfile, isLoading: Binding<Bool>) {
            self.profile = profile
            _isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            isLoading = false
        }

        /// Same policy as the API client: the pinned fingerprint, then system
        /// trust, then the explicit "skip verification" setting.
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            let outcome = TLSTrustDelegate.evaluate(
                fingerprint: TLSTrustDelegate.leafFingerprint(of: trust),
                pinned: profile.pinnedCertificateSHA256,
                systemTrusts: SecTrustEvaluateWithError(trust, nil),
                skipVerification: profile.skipCertificateVerification)
            if outcome == .trusted {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
