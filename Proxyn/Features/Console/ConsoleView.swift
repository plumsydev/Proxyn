import SwiftUI
import WebKit

enum ConsoleTarget: Hashable {
    case guest(GuestRef)
    case node(String)
}

/// Embedded noVNC / xterm.js console. Proxmox's own web console is loaded in a
/// WKWebView with the session ticket injected as a cookie, which is the only way
/// to get a real framebuffer / shell on iOS without reimplementing VNC.
struct ConsoleView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: ConsoleTarget
    let title: String

    @State private var session: PVESession?
    @State private var error: String?
    @State private var loading = true
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let session, let url = consoleURL, let profile = app.selectedServer {
                    ConsoleWebView(url: url,
                                   ticket: session.ticket,
                                   host: profile.host,
                                   allowInsecureTLS: profile.allowInsecureTLS,
                                   isLoading: $loading)
                        .id(reloadToken)
                        .ignoresSafeArea(edges: .bottom)
                }

                if loading && error == nil {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Palette.ember)
                        Text("Ouverture de la console…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                if let error {
                    VStack(spacing: 16) {
                        EmptyStateView(symbol: "terminal", title: "Console indisponible", message: error)
                        Button("Fermer") { dismiss() }
                            .buttonStyle(QuietButtonStyle(tint: Palette.ember))
                    }
                    .padding(24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        loading = true
                        reloadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Palette.ember)
                    }
                }
            }
        }
        .presentationBackground(.black)
        .task { await prepare() }
    }

    private var consoleURL: URL? {
        guard let profile = app.selectedServer, let base = profile.baseURL else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = []

        switch target {
        case .guest(let ref):
            if ref.kind == .qemu {
                items = [.init(name: "console", value: "kvm"),
                         .init(name: "novnc", value: "1"),
                         .init(name: "vmid", value: String(ref.vmid)),
                         .init(name: "node", value: ref.node),
                         .init(name: "resize", value: "scale"),
                         .init(name: "cmd", value: "")]
            } else {
                items = [.init(name: "console", value: "lxc"),
                         .init(name: "xtermjs", value: "1"),
                         .init(name: "vmid", value: String(ref.vmid)),
                         .init(name: "node", value: ref.node),
                         .init(name: "cmd", value: "")]
            }
        case .node(let node):
            items = [.init(name: "console", value: "shell"),
                     .init(name: "xtermjs", value: "1"),
                     .init(name: "node", value: node),
                     .init(name: "cmd", value: "")]
        }

        components?.queryItems = items
        return components?.url
    }

    private func prepare() async {
        guard let client = app.client() else {
            error = "Aucun serveur sélectionné."
            loading = false
            return
        }
        do {
            session = try await client.consoleCredentials()
        } catch let err as ProxmoxError {
            error = err.localizedDescription
            loading = false
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

private struct ConsoleWebView: UIViewRepresentable {
    let url: URL
    let ticket: String
    let host: String
    let allowInsecureTLS: Bool
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(allowInsecureTLS: allowInsecureTLS, isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false

        // The console page authenticates from the PVEAuthCookie alone.
        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .domain: host,
            .path: "/",
            .name: "PVEAuthCookie",
            .value: ticket,
            .secure: "TRUE",
            .version: "0"
        ]
        if let cookie = HTTPCookie(properties: cookieProperties) {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                webView.load(URLRequest(url: url))
            }
        } else {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let allowInsecureTLS: Bool
        @Binding private var isLoading: Bool

        init(allowInsecureTLS: Bool, isLoading: Binding<Bool>) {
            self.allowInsecureTLS = allowInsecureTLS
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

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard allowInsecureTLS,
                  challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}
