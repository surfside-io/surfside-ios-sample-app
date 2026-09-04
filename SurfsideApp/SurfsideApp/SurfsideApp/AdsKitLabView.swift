import SwiftUI
import SurfsideAdsKit
import SurfsideTracker

// ============================================================================
// AdsKit Lab — the one comprehensive testing/demo area for SurfsideAdsKit.
// Replaces the old Bridge Spike and AdsKit demo tabs (archived in the tickets
// workspace under JJRC-338/spike/).
//
// Everything the kit does, exercised end to end on-device:
//   1. Identity      — explicit Configuration.userId vs auto-acquired tracker
//                      domainUserId (Obj-C reflection), the resolution preview,
//                      and what the fetch WebView's surfid cookie gets seeded with.
//   2. Carousel      — hidden-WebView product fetch (offscreen-hosted), with the
//                      no-fill vs timeout split surfaced.
//   3. Impressions   — pixels suppressed at fetch; recordImpression fires the
//                      win + impression trackers on real display, per product.
//   4. Banner        — visible SurfsideBanner: fill with rendered-size readback,
//                      no-fill collapse, clickthrough via SFSafariViewController.
// Every outcome lands in the event log at the bottom.
// ============================================================================

@available(iOS 15.0, *)
@MainActor
final class AdsKitLabModel: ObservableObject {

    // MARK: Placements (verified live tenants)

    // JARS Cannabis; 3ZG7D is its carousel zone (verified live fill).
    static let carouselAccount = (accountId: "4c9d3", siteId: "23191",
                                  channelId: "00000",
                                  locationId: "fe025dd0-85c4-4041-bc15-1051def8aa49")
    static let carouselZone = "3ZG7D"

    // Green Goddess; 6ambm is its banner zone.
    static let bannerAccount = (accountId: "ec981", siteId: "544fa",
                                channelId: "00000", locationId: "greengoddess")
    static let bannerZone = "6ambm"

    // MARK: Log

    struct LogLine: Identifiable {
        let id = UUID()
        let time: Date
        let tag: String
        let text: String
    }
    @Published var log: [LogLine] = []

    func logLine(_ tag: String, _ text: String) {
        log.append(LogLine(time: Date(), tag: tag, text: text))
        print("🧪 AdsKitLab \(tag) \(text)")
    }

    // MARK: Identity (JJRC-259 manual + JJRC-456 auto)

    enum IdentityMode: String, CaseIterable, Identifiable {
        case auto = "Auto (tracker)"
        case explicitId = "Explicit"
        var id: String { rawValue }
    }
    @Published var identityMode: IdentityMode = .auto
    @Published var explicitUserId: String = "lab-explicit-user-123"
    @Published var trackerIdentity: [String: String] = [:]

    /// The userId the next fetch's Configuration carries (nil lets AdsKit
    /// auto-acquire over reflection).
    var configuredUserId: String? {
        identityMode == .explicitId ? explicitUserId : nil
    }

    /// Local mirror of AdsKit's resolution order (explicit > auto > anonymous),
    /// so the UI can show what the surfid cookie is expected to be seeded with.
    var expectedResolvedId: String? {
        if let explicit = configuredUserId, !explicit.isEmpty { return explicit }
        if let auto = trackerIdentity["domainUserId"], !auto.isEmpty { return auto }
        return nil
    }

    func refreshTrackerIdentity() {
        // Direct call here; AdsKit itself reaches the same API over Obj-C
        // reflection (no SPM dependency), which is the path under test.
        trackerIdentity = SurfsideEvent().getResolvedIdentity()
        if let id = trackerIdentity["domainUserId"], !id.isEmpty {
            logLine("🪪", "tracker domainUserId = \(id)")
        } else {
            logLine("🪪", "tracker has no domainUserId (initialize the tracker in the Tracker Demo tab, then refresh)")
        }
    }

    // MARK: Carousel fetch (JJRC-338 half 1, carrying identity)

    enum FetchStatus: Equatable {
        case idle, loading, loaded(Int, seconds: Double), empty, failed(String)
    }
    @Published var products: [SurfsideProduct] = []
    @Published var fetchStatus: FetchStatus = .idle
    @Published var maxItems: Int = 4

    /// The instance that made the last fetch; recordImpression/recordClick must
    /// go through it. Rebuilt per fetch so identity-mode changes take effect.
    private(set) var ads: SurfsideAds?

    func fetchCarousel() {
        let cfg = SurfsideAds.Configuration(
            accountId: Self.carouselAccount.accountId,
            siteId: Self.carouselAccount.siteId,
            channelId: Self.carouselAccount.channelId,
            locationId: Self.carouselAccount.locationId,
            isInspectable: true,
            userId: configuredUserId
        )
        let ads = SurfsideAds(configuration: cfg)
        self.ads = ads

        fetchStatus = .loading
        products = []
        firedImpressions = []
        impressionResults = [:]
        logLine("🛒", "fetch: zone \(Self.carouselZone), maxItems \(maxItems), userId \(configuredUserId ?? "nil (auto)") → expect cookie \(expectedResolvedId ?? "none (anonymous)")")

        let started = Date()
        ads.fetchProducts(zoneId: Self.carouselZone, maxItems: maxItems, strategy: .hybrid) { [weak self] result in
            guard let self = self else { return }
            let elapsed = Date().timeIntervalSince(started)
            switch result {
            case .success(let items):
                self.products = items
                self.fetchStatus = items.isEmpty
                    ? .empty
                    : .loaded(items.count, seconds: elapsed)
                let trackers = items.map { "\($0.winTrackers?.count ?? 0)w/\($0.impressionTrackers?.count ?? 0)i/\($0.viewableTrackers?.count ?? 0)v" }
                self.logLine("🛒", items.isEmpty
                    ? "SDK ran, zone served nothing (clean empty, not a timeout) in \(String(format: "%.1f", elapsed))s"
                    : "\(items.count) products in \(String(format: "%.1f", elapsed))s, trackers per product: \(trackers.joined(separator: ", "))")
            case .failure(let error):
                self.fetchStatus = .failed(error.localizedDescription)
                self.logLine("🛒", "failed: \(error)")
            }
        }
    }

    // MARK: Impressions (JJRC-338 half 2)

    @Published var firedImpressions: Set<String> = []
    @Published var impressionResults: [String: Bool] = [:]

    func recordImpression(_ product: SurfsideProduct) {
        guard let ads = ads else { return }
        let urls = product.winTrackerURLs + product.impressionTrackerURLs
        if firedImpressions.contains(product.id) {
            logLine("👁", "re-firing \(product.id) (contract is once per display; this is a lab override)")
        }
        firedImpressions.insert(product.id)
        logLine("👁", "recordImpression \(product.id): firing \(urls.count) pixel(s) \(urls.map { $0.host ?? "?" }.joined(separator: ", "))")
        ads.recordImpression(product) { [weak self] allOK in
            DispatchQueue.main.async {
                self?.impressionResults[product.id] = allOK
                self?.logLine("👁", "recordImpression \(product.id) completed, allOK = \(allOK)")
            }
        }
    }

    func recordClick(_ product: SurfsideProduct) {
        guard let ads = ads else { return }
        logLine("🖱", "recordClick \(product.id)")
        ads.recordClick(product) { [weak self] ok in
            DispatchQueue.main.async {
                self?.logLine("🖱", "recordClick \(product.id) completed, ok = \(ok)")
            }
        }
    }

    // MARK: Banner (JJRC-338 banners)

    enum BannerSize: String, CaseIterable, Identifiable {
        case standard = "320×50"
        case mrec = "300×250"
        var id: String { rawValue }
        var cgSize: CGSize {
            self == .standard ? CGSize(width: 320, height: 50)
                              : CGSize(width: 300, height: 250)
        }
    }
    @Published var bannerSize: BannerSize = .standard
    @Published var bannerStatus: String = "not loaded"
    @Published var bannerCollapsed = false
    /// Bumping this recreates the SwiftUI banner (its placement is fixed at init).
    @Published var bannerToken = 0

    func reloadBanner() {
        bannerStatus = "loading \(bannerSize.rawValue)…"
        bannerCollapsed = false
        bannerToken += 1
        logLine("🖼", "banner load: zone \(Self.bannerZone), requested \(bannerSize.rawValue)")
    }

    func bannerLoaded(_ size: CGSize?) {
        let rendered = size.map { "\(Int($0.width))×\(Int($0.height))" } ?? "not reported"
        bannerStatus = "filled, rendered size \(rendered)"
        logLine("🖼", "banner filled; rendered size readback: \(rendered). Tap it to test clickthrough (should open in-app Safari).")
    }

    func bannerNoFill() {
        bannerStatus = "no fill (view collapsed)"
        bannerCollapsed = true
        logLine("🖼", "banner no-fill; view collapsed to zero height")
    }

    func bannerFailed(_ error: SurfsideAdsError) {
        bannerStatus = "failed: \(error)"
        bannerCollapsed = true
        logLine("🖼", "banner failed: \(error)")
    }
}

// MARK: - View

@available(iOS 15.0, *)
struct AdsKitLabView: View {
    @StateObject private var model = AdsKitLabModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identitySection
                Divider()
                carouselSection
                Divider()
                bannerSection
                Divider()
                logSection
            }
            .padding()
        }
        .navigationTitle("AdsKit Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refreshTrackerIdentity()
            // `-labAutoRun` (e.g. via `simctl launch booted <bundle> -tab 2
            // -labAutoRun`) kicks off the fetch and banner load unattended, for
            // demos and screenshot runs.
            if ProcessInfo.processInfo.arguments.contains("-labAutoRun"),
               model.fetchStatus == .idle {
                model.fetchCarousel()
                model.reloadBanner()
            }
        }
    }

    // MARK: Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("1 · Identity", "resolution: explicit > auto (tracker) > anonymous")

            Picker("Identity mode", selection: $model.identityMode) {
                ForEach(AdsKitLabModel.IdentityMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if model.identityMode == .explicitId {
                TextField("Configuration.userId", text: $model.explicitUserId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.footnote, design: .monospaced))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            HStack(spacing: 6) {
                infoRow("tracker domainUserId",
                        model.trackerIdentity["domainUserId"] ?? "none")
                Button {
                    model.refreshTrackerIdentity()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            infoRow("next fetch seeds surfid cookie with",
                    model.expectedResolvedId ?? "nothing (anonymous)")

            if (model.trackerIdentity["domainUserId"] ?? "").isEmpty {
                Label("No tracker id yet: initialize the tracker in the Tracker Demo tab, then refresh. Auto mode then exercises the JJRC-456 reflection path.",
                      systemImage: "info.circle")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Carousel + impressions

    private var carouselSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("2 · Carousel fetch + impressions",
                          "hidden offscreen WebView; pixels suppressed at fetch, fired via recordImpression")

            HStack {
                Button {
                    model.fetchCarousel()
                } label: {
                    Label(model.products.isEmpty ? "Fetch products" : "Refetch",
                          systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)

                Stepper("max \(model.maxItems)", value: $model.maxItems, in: 1...10)
                    .font(.footnote)
                    .fixedSize()
            }

            fetchStatusRow

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(model.products) { product in
                    LabProductCell(
                        product: product,
                        impressionFired: model.firedImpressions.contains(product.id),
                        impressionOK: model.impressionResults[product.id],
                        onImpression: { model.recordImpression(product) },
                        onClick: { model.recordClick(product) }
                    )
                }
            }
        }
    }

    @ViewBuilder private var fetchStatusRow: some View {
        switch model.fetchStatus {
        case .idle:
            Label("Not fetched yet", systemImage: "circle")
                .font(.footnote).foregroundColor(.secondary)
        case .loading:
            HStack { ProgressView(); Text("Fetching…").font(.footnote) }
        case .loaded(let n, let s):
            Label("\(n) products in \(String(format: "%.1f", s))s (offscreen-hosted WebView ran the SDK)",
                  systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundColor(.green)
        case .empty:
            Label("SDK ran, zone served nothing (clean empty, not a timeout)",
                  systemImage: "tray")
                .font(.footnote).foregroundColor(.orange)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.footnote).foregroundColor(.red)
        }
    }

    // MARK: Banner

    private var bannerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("3 · Banner",
                          "visible WebView; own pixels fire legitimately, tap opens in-app Safari")

            HStack {
                Picker("Size", selection: $model.bannerSize) {
                    ForEach(AdsKitLabModel.BannerSize.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    model.reloadBanner()
                } label: {
                    Label("Load", systemImage: "arrow.clockwise.circle.fill")
                }
                .buttonStyle(.bordered)
            }

            infoRow("status", model.bannerStatus)

            if model.bannerToken > 0 && !model.bannerCollapsed {
                SurfsideBanner(
                    configuration: .init(
                        accountId: AdsKitLabModel.bannerAccount.accountId,
                        siteId: AdsKitLabModel.bannerAccount.siteId,
                        channelId: AdsKitLabModel.bannerAccount.channelId,
                        locationId: AdsKitLabModel.bannerAccount.locationId,
                        isInspectable: true
                    ),
                    zoneId: AdsKitLabModel.bannerZone,
                    size: model.bannerSize.cgSize,
                    onLoad: { model.bannerLoaded($0) },
                    onNoFill: { model.bannerNoFill() },
                    onError: { model.bannerFailed($0) }
                )
                .id(model.bannerToken)
                .frame(width: model.bannerSize.cgSize.width,
                       height: model.bannerSize.cgSize.height)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
        }
    }

    // MARK: Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("4 · Event log", "")
                Spacer()
                Button("Clear") { model.log.removeAll() }
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 4) {
                if model.log.isEmpty {
                    Text("Nothing yet").font(.caption).foregroundColor(.secondary)
                }
                ForEach(model.log.reversed()) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.tag)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.time, style: .time)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }

    // MARK: Bits

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":").font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Product cell

@available(iOS 15.0, *)
private struct LabProductCell: View {
    let product: SurfsideProduct
    let impressionFired: Bool
    let impressionOK: Bool?
    let onImpression: () -> Void
    let onClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: product.image.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    case .failure: placeholder("exclamationmark.triangle")
                    case .empty: placeholder("photo")
                    @unknown default: placeholder("photo")
                    }
                }
                .frame(height: 100).frame(maxWidth: .infinity).clipped().cornerRadius(6)

                if product.sponsored {
                    Text("Sponsored")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white).clipShape(Capsule()).padding(6)
                }
            }

            Text(product.name ?? "Untitled")
                .font(.subheadline).fontWeight(.medium).lineLimit(2)
            if let price = product.salePrice ?? product.price {
                Text(price).font(.subheadline).fontWeight(.bold)
            }
            Text("id \(product.id) · \(product.winTrackers?.count ?? 0)w \(product.impressionTrackers?.count ?? 0)i \(product.viewableTrackers?.count ?? 0)v")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Button(action: onImpression) {
                    Label(impressionFired ? "Fired" : "Impression",
                          systemImage: impressionBadge)
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(impressionTint)

                Button(action: onClick) {
                    Label("Click", systemImage: "cursorarrow.click")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var impressionBadge: String {
        guard impressionFired else { return "eye" }
        switch impressionOK {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle.fill"
        case .none: return "hourglass"
        }
    }

    private var impressionTint: Color {
        guard impressionFired else { return .accentColor }
        switch impressionOK {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .gray
        }
    }

    private func placeholder(_ name: String) -> some View {
        ZStack { Color(.tertiarySystemBackground); Image(systemName: name).foregroundColor(.secondary) }
    }
}

@available(iOS 15.0, *)
#Preview {
    NavigationView { AdsKitLabView() }
}
