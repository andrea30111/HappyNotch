import SwiftUI
import WebKit

enum Neurons {
    static let page = URL(string: "https://neurons.reply.com/chat?agentId=01KWN6PHYKS2HYK4VN0JJSZN53")!
}

/// Reply Neurons chat, shown inside the notch panel.
struct NeuronsView: View {
    @State private var loadError: String?
    @State private var reloadID = 0

    var body: some View {
        ZStack {
            NeuronsWebView(url: Neurons.page, loadError: $loadError, reloadID: reloadID)
            if let loadError {
                VStack(spacing: 8) {
                    Text("Couldn't open Neurons")
                        .font(.system(size: 13, weight: .semibold))
                    Text(loadError)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        self.loadError = nil
                        reloadID += 1
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.72))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Neurons")
    }
}

private struct NeuronsWebView: NSViewRepresentable {
    let url: URL
    @Binding var loadError: String?
    var reloadID: Int

    func makeCoordinator() -> Coordinator { Coordinator(loadError: $loadError) }

    func makeNSView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.loadError = $loadError
        guard context.coordinator.reloadID != reloadID else { return }
        context.coordinator.reloadID = reloadID
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadError: Binding<String?>
        var reloadID = 0
        weak var webView: WKWebView?

        init(loadError: Binding<String?>) {
            self.loadError = loadError
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            self.loadError.wrappedValue = error.localizedDescription
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
