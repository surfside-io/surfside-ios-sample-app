import SwiftUI
import SurfsideTracker

// MARK: - Commerce Catalog Model

/// A fully-specified demo product.
///
/// Every stored property maps 1:1 to a parameter of
/// `SurfsideEvent.addProduct(...)`, so a single `DemoProduct` value can
/// populate the *entire* commerce product context. Keeping the catalog in a
/// value type (rather than scattered literals inside button handlers) is what
/// makes the demo "configurable": add or edit an entry in `DemoProduct.catalog`
/// and every action button picks it up automatically.
struct DemoProduct: Identifiable {
    let id: String          // SKU / product id
    let name: String
    let list: String        // the list/collection the product was surfaced in
    let brand: String
    let category: String
    let variant: String
    let price: Double
    let quantity: Int
    let coupon: String
    let position: Int        // position within `list`
    let currency: String

    /// Line-item subtotal (price × quantity). Used to build transaction revenue.
    var lineTotal: Double { price * Double(quantity) }
}

extension DemoProduct {
    /// Two deliberately-distinct products (different brand, category, variant,
    /// price, and quantity) so the emitted contexts are easy to tell apart in
    /// the collector. Edit or extend this array to reconfigure the demo.
    static let catalog: [DemoProduct] = [
        DemoProduct(
            id: "SURF-AUD-001",
            name: "Aurora Wireless Headphones",
            list: "featured-products",
            brand: "Aurora Audio",
            category: "Electronics/Audio/Headphones",
            variant: "Midnight Black",
            price: 149.99,
            quantity: 1,
            coupon: "AURORA15",
            position: 1,
            currency: "USD"
        ),
        DemoProduct(
            id: "SURF-SHO-002",
            name: "Tidal Trail Running Shoes",
            list: "featured-products",
            brand: "Tidal",
            category: "Footwear/Running",
            variant: "Reef Blue / US 10",
            price: 89.50,
            quantity: 2,
            coupon: "TIDAL10",
            position: 2,
            currency: "USD"
        )
    ]
}

// MARK: - Commerce Action Model

/// The commerce actions this demo can fire. The `rawValue` is exactly the
/// string the SDK expects in `setCommerceAction(action:)` and that lands in the
/// `io.surfside.commerce/action` context, so the enum doubles as the wire value.
enum CommerceAction: String, CaseIterable, Identifiable {
    case detail
    case add
    case remove
    case cart
    case checkout
    case purchase

    var id: String { rawValue }

    /// Human-readable button label.
    var label: String {
        switch self {
        case .detail:   return "View Detail"
        case .add:      return "Add to Cart"
        case .remove:   return "Remove from Cart"
        case .cart:     return "View Cart"
        case .checkout: return "Checkout"
        case .purchase: return "Purchase"
        }
    }

    /// SF Symbol shown on the button.
    var symbol: String {
        switch self {
        case .detail:   return "magnifyingglass"
        case .add:      return "cart.badge.plus"
        case .remove:   return "cart.badge.minus"
        case .cart:     return "cart"
        case .checkout: return "creditcard"
        case .purchase: return "checkmark.seal"
        }
    }

    /// Whether the action should also carry a transaction context.
    /// Checkout and purchase are the points in the funnel where a
    /// transaction/order actually exists.
    var includesTransaction: Bool {
        self == .checkout || self == .purchase
    }
}

// MARK: - Content View

@available(iOS 14.0, macOS 11.0, *)
struct ContentView: View {
    @State private var tracker: (any TrackerController)? = nil
    @State private var surfsideEvent: SurfsideEvent? = nil
    @State private var logMessages: [String] = []
    @State private var isInitialized = false

    /// Which catalog products are included in the next commerce action.
    /// Defaults to everything selected so a fresh tap fires a multi-product event.
    @State private var selectedProductIDs: Set<String> = Set(DemoProduct.catalog.map(\.id))

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                statusView
                setupSection
                contextSection
                basicEventSection
                productSelectionSection
                commerceActionSection
                logSection
            }
            .padding()
        }
    }

    // MARK: Header / Status

    private var headerView: some View {
        Text("Surfside iOS SDK Demo")
            .font(.title)
            .padding(.top)
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

    // MARK: Setup section

    private var setupSection: some View {
        section(title: "Initialize, Debug, Clear", tint: .gray) {
            HStack(spacing: 12) {
                Button("Initialize") { initializeTracker() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInitialized)

                Button("Debug Flow") { debugEventFlow() }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)

                Button("Clear Logs") { logMessages.removeAll() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Context section

    private var contextSection: some View {
        section(title: "Set Contexts", tint: .blue) {
            HStack(spacing: 12) {
                Button("Update Location") { updateLocation() }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)

                Button("Update Source") { updateSource() }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)

                Button("Update Segment") { updateSegment() }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)
            }
        }
    }

    // MARK: Basic events section

    private var basicEventSection: some View {
        section(title: "Basic Events", tint: .orange) {
            HStack(spacing: 12) {
                Button("Track Screen View") { trackScreenView() }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)

                Button("Track Link Click") { trackEvent() }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized)
            }
        }
    }

    // MARK: Product selection section

    private var productSelectionSection: some View {
        section(title: "Products in Commerce Action", tint: .purple) {
            VStack(spacing: 8) {
                ForEach(DemoProduct.catalog) { product in
                    productToggle(for: product)
                }
                Text("Selected products are attached to every commerce action below.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func productToggle(for product: DemoProduct) -> some View {
        Toggle(isOn: bindingForProduct(product.id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.subheadline)
                Text("\(product.brand) · \(product.variant) · \(product.price, specifier: "%.2f") \(product.currency) ×\(product.quantity)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(!isInitialized)
    }

    /// A `Binding<Bool>` backed by membership in `selectedProductIDs`.
    /// SwiftUI's `Toggle` needs a two-way binding; we synthesize one from the
    /// Set so toggling inserts/removes the id instead of tracking a separate flag.
    private func bindingForProduct(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedProductIDs.contains(id) },
            set: { isOn in
                if isOn { selectedProductIDs.insert(id) }
                else { selectedProductIDs.remove(id) }
            }
        )
    }

    // MARK: Commerce action section

    private var commerceActionSection: some View {
        section(title: "Commerce Actions", tint: .green) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CommerceAction.allCases) { action in
                    Button {
                        fire(action)
                    } label: {
                        Label(action.label, systemImage: action.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isInitialized || selectedProductIDs.isEmpty)
                }
            }
        }
    }

    // MARK: Log section

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Event Log")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logMessages.enumerated()), id: \.offset) { index, message in
                        logMessageView(index: index, message: message)
                    }
                }
            }
            .frame(maxHeight: 220)
            .border(Color.gray.opacity(0.3))
        }
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

    // MARK: - Reusable section container

    /// A titled, tinted card. `@ViewBuilder` lets callers pass arbitrary view
    /// trees as the trailing closure, so every section shares one layout.
    private func section<Content: View>(
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding()
        .background(tint.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Logging helper

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append("[\(timestamp)] \(message)")
    }

    /// Format a currency amount for log strings.
    ///
    /// Why not `\(value, specifier: "%.2f")`? That interpolation exists only on
    /// SwiftUI's `LocalizedStringKey` (used inside `Text`), not on plain
    /// `String`. `addLog` takes a `String`, so we format explicitly.
    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Commerce firing (unified)

    /// The currently-selected products, in catalog order.
    private var selectedProducts: [DemoProduct] {
        DemoProduct.catalog.filter { selectedProductIDs.contains($0.id) }
    }

    /// Fire a single commerce action carrying every selected product (with all
    /// attributes populated) and, for checkout/purchase, a full transaction.
    ///
    /// Flow: `addProduct` accumulates one product context per call; then
    /// `setCommerceAction` emits ONE event carrying all of them and clears the
    /// accumulated contexts. `setCommerceAction` flushes internally, so we don't
    /// flush again here.
    private func fire(_ action: CommerceAction) {
        guard let tracker = tracker, let surfsideEvent = surfsideEvent else {
            addLog("❌ Tracker not initialized")
            return
        }
        let products = selectedProducts
        guard !products.isEmpty else {
            addLog("⚠️ No products selected — nothing to fire")
            return
        }

        // Ensure the tracker is registered so accumulated contexts resolve.
        surfsideEvent.registerTracker(tracker)

        addLog("🛍️ Action '\(action.rawValue)' with \(products.count) product(s)")

        for product in products {
            addProductContext(product, using: surfsideEvent)
            addLog("  • \(product.name) [\(product.id)] \(money(product.price)) \(product.currency) ×\(product.quantity)")
        }

        if action.includesTransaction {
            addTransactionContext(for: products, action: action, using: surfsideEvent)
        }

        surfsideEvent.setCommerceAction(action: action.rawValue)
        addLog("✅ '\(action.rawValue)' event tracked and flushed")
    }

    /// Add one product context with EVERY attribute populated.
    ///
    /// Note the `as NSNumber` bridges: the SDK's `addProduct` takes `NSNumber?`
    /// for the numeric params. A Swift `Double`/`Int` *variable* doesn't
    /// implicitly convert (only literals do), so we bridge explicitly via
    /// Foundation's `Double`/`Int` → `NSNumber` bridging.
    private func addProductContext(_ product: DemoProduct, using surfsideEvent: SurfsideEvent) {
        surfsideEvent.addProduct(
            id: product.id,
            name: product.name,
            list: product.list,
            brand: product.brand,
            category: product.category,
            variant: product.variant,
            price: product.price as NSNumber,
            quantity: product.quantity as NSNumber,
            coupon: product.coupon,
            position: product.position as NSNumber,
            currency: product.currency,
            trackerNamespaces: nil
        )
    }

    /// Add a transaction context covering the selected products, with every
    /// attribute populated. Revenue is derived from the line totals so the
    /// numbers stay internally consistent.
    private func addTransactionContext(
        for products: [DemoProduct],
        action: CommerceAction,
        using surfsideEvent: SurfsideEvent
    ) {
        let subtotal = products.reduce(0) { $0 + $1.lineTotal }
        let tax = (subtotal * 0.08).rounded(toPlaces: 2)
        let shipping = 5.99
        let revenue = (subtotal + tax + shipping).rounded(toPlaces: 2)
        let currency = products.first?.currency ?? "USD"

        // Checkout is step 1 (entering the flow); purchase is the completed step 2.
        let step = action == .checkout ? 1 : 2
        let option = action == .checkout ? "Standard Shipping" : "Credit Card"

        surfsideEvent.addTransaction(
            id: "ORDER-\(action.rawValue.uppercased())-001",
            affiliation: "Surfside Demo Store",
            revenue: revenue as NSNumber,
            tax: tax as NSNumber,
            shipping: shipping as NSNumber,
            coupon: "ORDER20",
            list: products.first?.list,
            step: step as NSNumber,
            option: option,
            currency: currency,
            trackerNamespaces: nil
        )
        addLog("  🧾 txn revenue \(money(revenue)) \(currency) (sub \(money(subtotal)) + tax \(money(tax)) + ship \(money(shipping))), step \(step), \(option)")
    }

    // MARK: - Tracker lifecycle

    func initializeTracker() {
        addLog("Starting tracker initialization...")

        let namespace = "iosTracker"
        let endpoint = "https://c-dev.surfside.io"
        let accountId = "00000-1-james"
        let sourceId = "00000-1-james"

        addLog("Creating tracker with namespace: \(namespace)")
        addLog("Endpoint: \(endpoint)")
        addLog("Account ID: \(accountId), Source ID: \(sourceId)")

        let result = SurfsideHelper.createTracker(
            namespace: namespace,
            environment: .development,
            accountId: accountId,
            sourceId: sourceId
        )

        self.tracker = result.tracker
        self.surfsideEvent = result.plugin
        self.isInitialized = true

        addLog("✅ Tracker initialized")
        addLog("📡 Source event fired (accountId=\(accountId), sourceId=\(sourceId))")

        surfsideEvent?.setLocation(
            id: "James",
            latitude: "37.7749",
            longitude: "-122.4194",
            country_code: "US",
            state: "CA",
            city: "San Francisco",
            trackerNamespaces: nil
        )
        addLog("📍 Location set: San Francisco (37.7749, -122.4194)")

        tracker?.emitter?.flush()
        addLog("✅ Initialization complete — tracker ready for events")
    }

    func trackScreenView() {
        guard let tracker = tracker else {
            addLog("❌ Error: Tracker not initialized")
            return
        }
        addLog("🔥 Tracking screen view event...")
        _ = tracker.track(ScreenView(name: "Home"))
        tracker.emitter?.flush()
        addLog("✅ Screen view tracked and flushed")
    }

    func trackEvent() {
        guard let tracker = tracker else {
            addLog("❌ Error: Tracker not initialized")
            return
        }
        addLog("🔥 Tracking link click event...")
        let event = SelfDescribing(
            schema: "iglu:com.snowplowanalytics.snowplow/link_click/jsonschema/1-0-1",
            payload: ["targetUrl": "https://example.com"]
        )
        _ = tracker.track(event)
        tracker.emitter?.flush()
        addLog("✅ Link click tracked and flushed")
    }

    func debugEventFlow() {
        guard let tracker = tracker else {
            addLog("❌ Error: Tracker not initialized")
            return
        }
        addLog("🔍 Debug: Testing event flow...")
        addLog("🔍 Debug: Tracker namespace: \(tracker.namespace)")

        let testEvent = SelfDescribing(
            schema: "iglu:com.example/test_event/jsonschema/1-0-0",
            payload: ["test": "debug_flow", "timestamp": Date().timeIntervalSince1970]
        )
        _ = tracker.track(testEvent)
        tracker.emitter?.flush()
        addLog("🔍 Debug: Test complete — check network logs for delivery")
    }

    // MARK: - Context updates

    func updateLocation() {
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        addLog("📍 Updating location context...")
        surfsideEvent.setLocation(
            id: "James-2",
            latitude: "40.7128",
            longitude: "-74.0060",
            country_code: "US",
            state: "NY",
            city: "New York",
            trackerNamespaces: nil
        )
        addLog("✅ Location updated: New York (40.7128, -74.0060)")
        tracker?.emitter?.flush()
        addLog("🚀 Location update flushed to collector")
    }

    func updateSource() {
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        addLog("📡 Updating source context...")
        surfsideEvent.source(
            accountId: "00000-2-james",
            sourceId: "00000-2-james",
            trackerNamespaces: nil
        )
        addLog("✅ Source updated: accountId=00000-2-james, sourceId=00000-2-james")
        tracker?.emitter?.flush()
        addLog("🚀 Source update flushed to collector")
    }

    func updateSegment() {
        guard let surfsideEvent = surfsideEvent else {
            addLog("❌ Error: SurfsideEvent not initialized")
            return
        }
        addLog("🎯 Updating segment context...")
        surfsideEvent.segment(
            segmentId: "james-users",
            segmentVal: "james-1",
            trackerNamespaces: nil
        )
        addLog("✅ Segment updated: james-users = james-1")
        tracker?.emitter?.flush()
        addLog("🚀 Segment update flushed to collector")
    }
}

// MARK: - Utilities

private extension Double {
    /// Round to a fixed number of decimal places so demo money values stay tidy.
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

@available(iOS 14.0, macOS 11.0, *)
#Preview {
    ContentView()
}
