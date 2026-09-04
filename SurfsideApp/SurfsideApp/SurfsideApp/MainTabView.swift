import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct MainTabView: View {
    // Launch with `-shopTab`, or `-tab N` (0-based), to open on a specific tab
    // (e.g. `simctl launch booted <bundle> -shopTab`) — handy for demos and
    // screenshots.
    @State private var selection: Int = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-shopTab") { return 3 }
        if let i = args.firstIndex(of: "-tab"), args.indices.contains(i + 1),
           let n = Int(args[i + 1]) { return n }
        return 0
    }()

    var body: some View {
        TabView(selection: $selection) {
            ContentView()
                .tag(0)
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Tracker Demo")
                }
            
            NavigationView {
                SurfsideAdsView()
            }
            .navigationViewStyle(.stack)
            .tag(1)
            .tabItem {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                Text("Surfside Ads")
            }

            if #available(iOS 15.0, *) {
                NavigationView {
                    AdsKitLabView()
                }
                .navigationViewStyle(.stack)
                .tag(2)
                .tabItem {
                    Image(systemName: "testtube.2")
                    Text("AdsKit Lab")
                }
            }

            if #available(iOS 15.0, *) {
                NavigationView {
                    ShopDemoView()
                }
                .navigationViewStyle(.stack)
                .tag(3)
                .tabItem {
                    Image(systemName: "bag")
                    Text("Shop")
                }
            }

        }
    }
}

@available(iOS 14.0, macOS 11.0, *)
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
