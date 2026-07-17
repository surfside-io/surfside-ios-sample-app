import SwiftUI
import SurfsideTracker

@available(iOS 14.0, macOS 11.0, *)
struct ContentView: View {
    @State private var tracker: (any TrackerController)? = nil
    @State private var surfsideEvent: SurfsideEvent? = nil
    @State private var logBlocks: [[String]] = []
    @State private var isInitialized = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerView
            statusView
            buttonSection
            logSection
        }
        .padding()
    }
    
    private var headerView: some View {
        Text("Surfside iOS SDK Demo")
            .font(.title)
            .padding()
    }
    
    private var statusView: some View {
        HStack {
            Circle()
                .fill(isInitialized ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            Text(isInitialized ? "Tracker Initialized" : "Not Initialized")
                .font(.caption)
        }
    }
    
    private var buttonSection: some View {
        VStack(spacing: 20) {
            // MARK: - Initialize, Debug, Clear Section
            VStack(spacing: 8) {
                Text("Initialize, Debug, Clear")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Button("Initialize Tracker") {
                        initializeTracker()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInitialized)
                    
                    Button("Debug Event Flow") {
                        debugEventFlow()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)
                    
                    Button("Clear Logs") {
                        logBlocks.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // MARK: - Set Contexts Section
            VStack(spacing: 8) {
                Text("Set Contexts")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Button("Update Location") {
                        updateLocation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)
                    
                    Button("Update Source") {
                        updateSource()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)
                    
                    Button("Update Segment") {
                        updateSegment()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
            
            // MARK: - Fire Events Section
            VStack(spacing: 8) {
                Text("Fire Events")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Track Screen View") {
                            trackScreenView()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isInitialized)
                        
                        Button("Track Basic Event") {
                            trackEvent()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isInitialized)
                    }
                    
                    HStack(spacing: 12) {
                        Button("View Product (Commerce)") {
                            viewProduct()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isInitialized)
                        
                        Button("Purchase Product") {
                            trackPurchase()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isInitialized)
                    }
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var logSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(logBlocks.enumerated()), id: \.offset) { blockIndex, block in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(block.enumerated()), id: \.offset) { lineIndex, message in
                                logMessageView(index: lineIndex, message: message)
                            }
                        }
                        .padding(.vertical, 2)

                        // Divider between each event block (not after the last)
                        if blockIndex < logBlocks.count - 1 {
                            Divider()
                                .frame(height: 1)
                                .background(Color.gray.opacity(0.5))
                        }
                    }

                    // Invisible anchor at the bottom to auto-scroll to
                    Color.clear
                        .frame(height: 1)
                        .id(logBottomAnchor)
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)
            .border(Color.gray.opacity(0.3))
            .onChange(of: totalLogLines) { _ in
                withAnimation {
                    proxy.scrollTo(logBottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    // Anchor id for the bottom of the log, and a count that changes whenever a
    // new line is added so we know when to auto-scroll to the latest message.
    private let logBottomAnchor = "logBottomAnchor"
    private var totalLogLines: Int {
        logBlocks.reduce(0) { $0 + $1.count }
    }

    private func logMessageView(index: Int, message: String) -> some View {
        Text("\(index + 1). \(message)")
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
    }

    // Start a new log block — call at the beginning of each user action so
    // its messages are visually grouped and separated from the previous action.
    private func beginLogBlock() {
        logBlocks.append([])
    }

    // Helper function to add log messages with timestamp
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)"
        if logBlocks.isEmpty {
            logBlocks.append([line])
        } else {
            logBlocks[logBlocks.count - 1].append(line)
        }
    }
    
    func initializeTracker() {
        beginLogBlock()
        addLog("Starting tracker initialization...")
        
        // Use SurfsideHelper to create a tracker with the Surfside plugin
        let namespace = "iosTracker"
        let endpoint = "https://c-dev.surfside.io"
        let accountId = "00000-1"
        let sourceId = "00000-2"
        
        addLog("Creating tracker with namespace: \(namespace)")
        addLog("Endpoint: \(endpoint)")
        addLog("Account ID: \(accountId), Source ID: \(sourceId)")
        
        // Create the tracker and plugin with SurfsideHelper
        // This will also register the tracker and fire the source event
        addLog("🔧 Creating tracker with POST method...")
        let result = SurfsideHelper.createTracker(
            namespace: namespace,
            environment: .development,
            accountId: accountId,
            sourceId: sourceId
        )
        
        // Add debugging for network configuration
        addLog("🌐 Network endpoint configured: \(endpoint)")
        addLog("📤 HTTP method: POST")
        
        // Store references for later use
        self.tracker = result.tracker
        self.surfsideEvent = result.plugin
        self.isInitialized = true
        
        addLog("✅ Tracker initialized successfully!")
        addLog("📡 Source event fired automatically by SurfsideHelper with accountId: \(accountId), sourceId: \(sourceId)")
        
        // Set location context after source
        surfsideEvent?.setLocation(
            latitude: "37.7749",
            longitude: "-122.4194",
            country_code: "US",
            state: "CA",
            city: "San Francisco",
            trackerNamespaces: nil
        )
        addLog("📍 Location set: San Francisco (37.7749, -122.4194)")
        
        // Force flush any pending events
        addLog("🚀 Flushing any pending events...")
        tracker?.emitter?.flush()
        addLog("✅ Initialization complete - tracker ready for events")
    }

    func trackScreenView() {
        beginLogBlock()
        guard let tracker = tracker else {
            addLog("❌ Error: Tracker not initialized")
            return
        }
        
        addLog("🔥 Tracking basic screen viewed event...")
        
        _ = tracker.track(ScreenView(name: "Home"))
        tracker.emitter?.flush()
        
        addLog("✅ Basic event tracked and flushed")
    }
    
    func trackEvent() {
        beginLogBlock()
        guard let tracker = tracker else {
            addLog("❌ Error: Tracker not initialized")
            return
        }
        
        addLog("🔥 Tracking basic link click event...")
        
        let event = SelfDescribing(
            schema: "iglu:com.snowplowanalytics.snowplow/link_click/jsonschema/1-0-1",
            payload: ["targetUrl": "https://example.com"]
        )
        
        addLog("Event schema: link_click")
        addLog("Event payload: targetUrl = https://example.com")
        
        _ = tracker.track(event)
        tracker.emitter?.flush()
        
        addLog("✅ Basic event tracked and flushed")
    }
    
    func debugEventFlow() {
        beginLogBlock()
        guard let tracker = tracker else {
            addLog("❌ Error: Tracker not initialized")
            return
        }
        
        addLog("🔍 Debug: Testing event flow...")
        addLog("🔍 Debug: Tracker namespace: \(tracker.namespace)")

        // Test network connectivity by sending a simple event
        let testEvent = SelfDescribing(
            schema: "iglu:com.example/test_event/jsonschema/1-0-0",
            payload: ["test": "debug_flow", "timestamp": Date().timeIntervalSince1970]
        )
        
        addLog("🔍 Debug: Sending test event...")
        _ = tracker.track(testEvent)
        
        // Force immediate flush
        addLog("🔍 Debug: Forcing flush...")
        tracker.emitter?.flush()
        
        addLog("🔍 Debug: Test complete - check network logs for delivery")
    }
    
    func updateLocation() {
        beginLogBlock()
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        
        addLog("📍 Updating location context...")
        
        // Update location with new coordinates (example: New York)
        surfsideEvent.setLocation(
            latitude: "40.7128",
            longitude: "-74.0060",
            country_code: "US",
            state: "NY",
            city: "New York",
            trackerNamespaces: nil
        )
        
        addLog("✅ Location updated: New York (40.7128, -74.0060)")
        
        // Force flush to send the location update
        tracker?.emitter?.flush()
        addLog("🚀 Location update flushed to collector")
    }
    
    func updateSource() {
        beginLogBlock()
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        
        addLog("📡 Updating source context...")
        
        // Update source with new account and source IDs
        surfsideEvent.source(
            accountId: "updated-account-123",
            sourceId: "updated-source-456",
            trackerNamespaces: nil
        )
        
        addLog("✅ Source updated: accountId=updated-account-123, sourceId=updated-source-456")
        
        // Force flush to send the source update
        tracker?.emitter?.flush()
        addLog("🚀 Source update flushed to collector")
    }
    
    func updateSegment() {
        beginLogBlock()
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        
        addLog("🎯 Updating segment context...")
        
        // Update segment with new segment data
        surfsideEvent.segment(
            segmentId: "premium-users",
            segmentVal: "1",
            trackerNamespaces: nil
        )
        
        addLog("✅ Segment updated: premium-users (Premium Subscribers)")
        
        // Force flush to send the segment update
        tracker?.emitter?.flush()
        addLog("🚀 Segment update flushed to collector")
    }
    
    func trackPurchase() {
        beginLogBlock()
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        
        addLog("🛒 Tracking purchase event...")
        
        // Add purchase product
        surfsideEvent.addProduct(
            id: "demo-product-123",
            name: "Sample Product",
            list: "featured-products",
            brand: "Demo Brand",
            category: "Electronics",
            variant: "Blue",
            price: 29.99,
            quantity: 1,
            coupon: "SAVE10",
            position: 1,
            currency: "USD",
            trackerNamespaces: nil
        )
        
        addLog("➕ Added purchase product: Sample Product ($29.99 x1)")
        
        // Set commerce action to purchase
        surfsideEvent.setCommerceAction(action: "purchase")
        addLog("🛒 Purchase event fired for demo-product-123 ($29.99)")
        
        // Force flush events
        tracker?.emitter?.flush()
        addLog("🚀 Purchase events flushed to collector")
    }
    
    func viewProduct() {
        beginLogBlock()
        guard let tracker = tracker, let surfsideEvent = self.surfsideEvent else {
            addLog("❌ Error: Tracker or SurfsideEvent not initialized")
            return
        }
        
        addLog("🛍️ Starting commerce product view flow...")
        
        // Force register the tracker with SurfsideController
        surfsideEvent.registerTracker(tracker)
        addLog("🔗 Tracker registered with SurfsideController")
        
        // Add product to the commerce context FIRST
        addLog("📦 Adding product context:")
        addLog("  - ID: P12345")
        addLog("  - Name: Premium Product")
        addLog("  - Price: $29.99")
        addLog("  - Quantity: 2")

        surfsideEvent.addProduct(
            id: "P12345",
            name: "Premium Product",
            price: 29.99,
            quantity: 2
        )
        
        addLog("✅ Product context added to tracker")
        
        // Set commerce action to "detail" (product view)
        addLog("🔍 Setting commerce action: 'detail'")
        addLog("📡 This will create commerce action event with attached product context")
        
        surfsideEvent.setCommerceAction(action: "detail")
        
        addLog("✅ Commerce action event tracked with product context")
        
        // Force flush events
        tracker.emitter?.flush()
        addLog("🚀 Events flushed to collector")
    }
}

@available(iOS 14.0, macOS 11.0, *)
#Preview {
    ContentView()
}
