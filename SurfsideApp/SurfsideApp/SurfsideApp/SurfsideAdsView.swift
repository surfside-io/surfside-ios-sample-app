import SwiftUI
import WebKit

@available(iOS 14.0, macOS 11.0, *)
struct SurfsideAdsView: View {
    @State private var webView = WKWebView()
    @State private var navigateToBrand: String? = nil
    @State private var isNavigatingToBrand = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Text("Surfside Ads")
                    .font(.title)
                    .padding()
                
                WebViewRepresentable(
                    webView: $webView,
                    navigateToBrand: $navigateToBrand
                )
                .onAppear {
                    loadSurfsideAd()
                }
            }
            
            // Hidden NavigationLink for programmatic navigation
            NavigationLink(
                destination: navigateToBrand.map { BrandPageView(brandName: $0) },
                isActive: $isNavigatingToBrand
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationTitle("Surfside Ads")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: navigateToBrand) { brandName in
            if brandName != nil {
                isNavigatingToBrand = true
            }
        }
        .onChange(of: isNavigatingToBrand) { isActive in
            if !isActive {
                // Reset when user navigates back
                navigateToBrand = nil
            }
        }
    }
    
    private func loadSurfsideAd() {
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Surfside Ads</title>
           
        </head>
        <body>
            <div class="ad-container">
                <div class="ad-title">Surf Banner @ 4:1</div>
                <surf-banner 
                    channel-id="00000" 
                    account-id="00000" 
                    site-id="00000" 
                    placement-id="00000"
                    location-id="UNIQUE_STORE_ID_HERE"
                    zone="myzone"
                    width="4" 
                    height="1">
                </surf-banner>
            </div>
            
            <div class="ad-container">
                <div class="ad-title">Live Banner [Argonaut] @ 8:1</div>
                <surf-banner 
                    channel-id="482cf" 
                    account-id="6f05b" 
                    site-id="0f88f" 
                    placement-id="39225"
                    location-id="91067"
                    zone="myzone2"
                    width="8" 
                    height="1">
                </surf-banner>
                <div class="ad-title">Surf Banner @ 8:1</div>
                <surf-banner 
                    channel-id="482cf" 
                    account-id="94907" 
                    site-id="a63ef" 
                    placement-id="39226"
                    location-id="91067"
                    zone="myzone3"
                    width="8" 
                    height="1">
                </surf-banner>
            </div>
            
            <div class="ad-container">
                <div class="ad-title">Surf Banner @ 2:1</div>
                <surf-banner 
                    channel-id="00002" 
                    account-id="00000" 
                    site-id="00000" 
                    placement-id="00002"
                    location-id="UNIQUE_STORE_ID_HERE"
                    zone="myzone3"
                    width="2" 
                    height="1">
                </surf-banner>
            </div>
            
            <script src="//cdn.surfside.io/ads/2.0.0/r.js"></script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://internalhost.com"))
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    @Binding var webView: WKWebView
    @Binding var navigateToBrand: String?
    
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update coordinator's binding
        context.coordinator.navigateToBrand = $navigateToBrand
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, navigateToBrand: $navigateToBrand)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable
        var navigateToBrand: Binding<String?>
        
        init(_ parent: WebViewRepresentable, navigateToBrand: Binding<String?>) {
            self.parent = parent
            self.navigateToBrand = navigateToBrand
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ Surfside Ads WebView loaded successfully")
            
            if let url = webView.url {
                let scheme = url.scheme       // "https" or "myapp"
                let host = url.host           // "example.com"
                let absolute = url.absoluteString
                
                print("🔍 URL Scheme: \(scheme ?? "nil")")
                print("🔍 URL Host: \(host ?? "nil")")
                print("🔍 URL Absolute: \(absolute)")
            } else {
                print("🔍 WebView URL is nil")
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Surfside Ads WebView failed to load: \(error.localizedDescription)")
            print("🔍 Failed URL: \(webView.url?.absoluteString ?? "nil")")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                print("❌ Navigation action has no URL")
                decisionHandler(.cancel)
                return
            }
            
            // Log URL components for navigation requests
            let scheme = url.scheme       // "https" or "myapp"
            let host = url.host           // "example.com"
            let absolute = url.absoluteString
            let path = url.path
            
            print("🔍 Navigation Request URL Components:")
            print("   Scheme: \(scheme ?? "nil")")
            print("   Host: \(host ?? "nil")")
            print("   Path: \(path)")
            print("   Absolute: \(absolute)")
            print("🔍 Navigation type: \(navigationAction.navigationType.rawValue)")
            print("🔍 Request headers: \(navigationAction.request.allHTTPHeaderFields ?? [:])")
            
            // Special handling for URLs that might be missing scheme
            // If absolute URL looks like "internalhost.com/brand/..." without scheme
            if scheme == nil && absolute.starts(with: "internalhost.com") {
                print("⚠️ URL missing scheme, treating as internal host")
            }
            
            // Approach 1: Allow tracker clickthrough, then intercept the redirect to route internally
            // Define internal hosts that should be routed in-app (HOSTNAME ONLY, no scheme)
            let internalHosts: Set<String> = [
                "internalhost.com"
            ]

            // Some ads open in a new window (target=_blank). When targetFrame is nil,
            // treat it as a normal navigation so we can apply the same interception logic.
            if navigationAction.targetFrame == nil {
                print("🪟 New-window click detected for: \(absolute)")
            }
            
            // 1) If this is a tracker clickthrough (e.g., rtb.surfside.io/callback?...&url=ENCODED)
            //    let it proceed so the click is recorded server-side
            if let h = host, h.contains("rtb.surfside.io") || h.hasSuffix("surfside.io") {
                print("🛰️ Allowing tracker clickthrough to proceed: \(absolute)")
                decisionHandler(.allow)
                return
            }
            
            // 2) If the request is to an internal host AND the path should be routed in-app,
            //    cancel WebView navigation and route internally
            let isRelative = (host == nil)
            let isInternalHost = (host.map { internalHosts.contains($0) } ?? false)
            
            // Also check if the absolute URL starts with an internal host (for URLs without scheme)
            let startsWithInternalHost = internalHosts.contains { absolute.starts(with: "\($0)/") || absolute.starts(with: "http://\($0)") || absolute.starts(with: "https://\($0)") }
            
            let hasLocationPath = path.contains("/location/") || path.contains("/locations/")
            let hasBrandPath = path.contains("/brand/")
            let shouldRouteInApp = (isInternalHost || isRelative || startsWithInternalHost) && (hasLocationPath || hasBrandPath)
            if shouldRouteInApp {
                let internalPath = path.isEmpty ? "/" : path
                let queryString = url.query.map { "?\($0)" } ?? ""
                print("✅ Intercepted internal destination. Routing in-app to: \(internalPath)\(queryString)")
                print("   isInternalHost: \(isInternalHost), startsWithInternalHost: \(startsWithInternalHost)")
                routeInternally(path: internalPath, query: url.query)
                decisionHandler(.cancel)
                return
            }
            
            // 3) Default behavior: allow external navigation
            print("🌐 Allowing external navigation: \(absolute)")
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ Surfside Ads WebView provisional navigation failed: \(error.localizedDescription)")
            if let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                print("🔍 Failing URL: \(failingURL.absoluteString)")
            }
        }
        
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            print("🔍 Authentication challenge for: \(challenge.protectionSpace.host)")
            
            // Handle Surfside domains with SSL certificate issues
            if challenge.protectionSpace.host.contains("surfside.io") {
                print("✅ Accepting SSL certificate for Surfside domain: \(challenge.protectionSpace.host)")
                
                // Create credential to accept the server certificate
                if let serverTrust = challenge.protectionSpace.serverTrust {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            } else {
                // For non-Surfside domains, use default handling
                completionHandler(.performDefaultHandling, nil)
            }
        }

        // MARK: - Helpers
        /// Extract query parameter value from a URL
        private func queryValue(for name: String, in url: URL) -> String? {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == name })?
                .value
        }
        
        /// Route internally based on path. Replace with your real navigation implementation.
        private func routeInternally(path: String, query: String? = nil) {
            let pathLower = path.lowercased()
            
            // Parse query parameters if present
            var params: [String: String] = [:]
            if let query = query {
                let queryItems = query.components(separatedBy: "&")
                for item in queryItems {
                    let parts = item.components(separatedBy: "=")
                    if parts.count == 2 {
                        params[parts[0]] = parts[1].removingPercentEncoding
                    }
                }
            }
            
            switch pathLower {
            case "/", "/home":
                print("📱 Navigate to Home")
            case "/products":
                print("📱 Navigate to Products")
            case let p where p.hasPrefix("/product/"):
                let productId = String(p.dropFirst("/product/".count))
                print("📱 Navigate to Product: \(productId)")
            case let c where c.hasPrefix("/category/"):
                let category = String(c.dropFirst("/category/".count))
                print("📱 Navigate to Category: \(category)")
            case let b where b.hasPrefix("/brand/"):
                // Extract brand name from path: /brand/fat tire
                let brandName = String(b.dropFirst("/brand/".count))
                    .removingPercentEncoding ?? String(b.dropFirst("/brand/".count))
                print("📱 Navigate to Brand Page")
                print("   Brand: \(brandName)")
                if !params.isEmpty {
                    print("   Query params: \(params)")
                }
                
                // Trigger navigation to brand page
                DispatchQueue.main.async {
                    self.navigateToBrand.wrappedValue = brandName
                }
            case let l where l.hasPrefix("/locations/"):
                // Extract location info from path: /locations/IL/orland-hills/menu
                let locationPath = String(l.dropFirst("/locations/".count))
                let components = locationPath.components(separatedBy: "/")
                print("📱 Navigate to Location")
                print("   Path: \(locationPath)")
                if components.count >= 2 {
                    print("   State: \(components[0])")
                    print("   City: \(components[1])")
                }
                if let searchTerm = params["searchTerm"] {
                    print("   Search Term: \(searchTerm)")
                }
                // TODO: Implement your actual app navigation here
                // Example: navigateToLocation(state: components[0], city: components[1], searchTerm: searchTerm)
            default:
                print("📱 Unhandled internal path: \(path)")
                if !params.isEmpty {
                    print("   Query params: \(params)")
                }
            }
        }
    }
}

@available(iOS 14.0, macOS 11.0, *)
#Preview {
    NavigationView {
        SurfsideAdsView()
    }
}
