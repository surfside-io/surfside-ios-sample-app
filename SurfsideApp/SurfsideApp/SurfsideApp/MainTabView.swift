import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Tracker Demo")
                }
            
            NavigationView {
                SurfsideAdsView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                Text("Surfside Ads")
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
