//
//  BenchCore.swift
//  AdsKit Test Bench: runner, fetch helper, log tap, results file.
//
//  Plan and pass conditions: surfside-workflows tickets/scratch/adskit-device-test-plan.md
//

import SwiftUI
import UIKit
import WebKit
#if DEBUG
@testable import SurfsideAdsKit
#else
import SurfsideAdsKit
#endif

// MARK: - Log tap

/// Copies the process's stderr (where NSLog lands) so cases can assert on the SDK's own
/// page log. If nothing ever arrives (stderr not connected), log checks report "unverified".
final class LogTap {
    static let shared = LogTap()

    private let lock = NSLock()
    private var kept: [String] = []
    private var remainder = Data()
    private var savedStderr: Int32 = -1
    private let pipe = Pipe()
    private(set) var started = false

    func start() {
        guard !started else { return }
        started = true
        // Launched from the Home Screen there is no terminal on stderr, and NSLog then skips
        // it; this makes it write there anyway. A console that detaches mid-run (backgrounding,
        // airplane mode) must not kill the app with SIGPIPE either.
        setenv("CFLOG_FORCE_STDERR", "YES", 1)
        signal(SIGPIPE, SIG_IGN)
        savedStderr = dup(STDERR_FILENO)
        setvbuf(stderr, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self = self, !data.isEmpty else { return }
            data.withUnsafeBytes { _ = write(self.savedStderr, $0.baseAddress, data.count) }
            self.consume(data)
        }
    }

    private func consume(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        remainder.append(data)
        while let newline = remainder.firstIndex(of: 0x0A) {
            let lineData = remainder[remainder.startIndex..<newline]
            remainder.removeSubrange(remainder.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8),
                  line.contains("SurfsideAdsKit") else { continue }
            // The forwarded web console is about 500 lines per fetch; keep only identity lines.
            if line.contains("SurfsideAdsKit console"), !line.contains("initApi ›"),
               !line.contains("204 - No bids available") { continue }
            kept.append(line)
        }
    }

    var alive: Bool { lock.lock(); defer { lock.unlock() }; return !kept.isEmpty }
    func mark() -> Int { lock.lock(); defer { lock.unlock() }; return kept.count }
    func since(_ mark: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return mark < kept.count ? Array(kept[mark...]) : []
    }

    func wait(for text: String, after mark: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if since(mark).contains(where: { $0.contains(text) }) { return true }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return false
    }

    /// The user id the web SDK initialised each element with ("" = anonymous).
    static func initUsers(_ lines: [String], account: String) -> [String] {
        lines.compactMap { line in
            guard let range = line.range(of: "initApi › ") else { return nil }
            let tokens = line[range.upperBound...].split(separator: " ").map(String.init)
            guard tokens.first == account else { return nil }
            return tokens.count >= 5 ? tokens[4] : ""
        }
    }
}

// MARK: - Results

enum Verdict: String, Codable { case pass, fail, info, skipped, running, pending }

struct CaseResult: Codable, Identifiable {
    let id: String
    let title: String
    var verdict: Verdict
    var notes: [String]
    var started: Date?
    var seconds: Double?
}

struct BenchReport: Codable {
    var runId: String
    var device: String
    var os: String
    var build: String
    var createMode: String
    var started: Date
    var results: [CaseResult]
}

// MARK: - Fetch plumbing

struct Outcome {
    let result: Result<[SurfsideProduct], Error>?   // nil = completion never called
    let ms: Int
    var products: [SurfsideProduct] { (try? result?.get()) ?? [] }
    var succeeded: Bool { if case .success = result { return true }; return false }
    var filled: Bool { !products.isEmpty }
    var text: String {
        switch result {
        case .none: return "NEVER CALLED \(ms)ms"
        case .success(let p): return "ok(\(p.count)) \(ms)ms"
        case .failure(let e): return "\(e) \(ms)ms"
        }
    }
}

@MainActor
final class PendingFetch {
    private(set) var outcome: Outcome?
    private var waiters: [CheckedContinuation<Outcome, Never>] = []
    var calls = 0

    func complete(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        waiters.forEach { $0.resume(returning: outcome) }
        waiters = []
    }

    func wait() async -> Outcome {
        if let outcome = outcome { return outcome }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

/// Collects one case's checks.
@MainActor
final class Ctx {
    private(set) var notes: [String] = []
    private(set) var failed = false
    private(set) var informational = false
    unowned let bench: Bench

    private let startMark = LogTap.shared.mark()

    init(bench: Bench) { self.bench = bench }

    /// Every fetch succeeded, and any empty one is matched by a bidder 204 in the web SDK's
    /// console (a genuine no-bid, which is the bidder's call and not a failure).
    func expectFilled(_ outcomes: [Outcome], _ text: String) {
        let failed = outcomes.filter { !$0.succeeded }.count
        let empty = outcomes.filter { $0.succeeded && !$0.filled }.count
        let noBids = LogTap.shared.since(startMark).filter { $0.contains("204 - No bids available") }.count
        if empty > 0 { note("\(empty) empty, bidder 204s logged in this case: \(noBids)") }
        expect(failed == 0 && (empty == 0 || (LogTap.shared.alive && empty <= noBids)), text)
    }

    func note(_ text: String) { notes.append(text); NSLog("%@", "BENCH   " + text) }
    func expect(_ condition: Bool, _ text: String) {
        if !condition { failed = true }
        note((condition ? "ok: " : "FAIL: ") + text)
    }
    /// A log-based check; downgraded when the log tap never saw the SDK's log.
    func expectLog(_ condition: Bool, _ text: String) {
        if LogTap.shared.alive { expect(condition, text) } else { note("unverified (no log tap): " + text) }
    }
    func infoOnly() { informational = true }
    var verdict: Verdict { failed ? .fail : (informational ? .info : .pass) }
}

enum CaseKind: String { case auto, hands, hook }

struct BenchCase: Identifiable {
    let id: String
    let title: String
    let kind: CaseKind
    var long = false
    let run: @MainActor (Ctx) async -> Void
}

struct BannerSlot: Identifiable {
    let id = UUID()
    let configuration: SurfsideAds.Configuration
    let zoneId: String
    let ratio: CGSize
    var inList = false
}

// MARK: - Bench

@MainActor
final class Bench: ObservableObject {
    static let shared = Bench()
    static let processStart = Date()

    // Carousel (fills), banner that fills (staging), banner that never fills.
    static let account = "4c9d3", site = "23191", channel = "00000"
    static let location = "fe025dd0-85c4-4041-bc15-1051def8aa49"
    static let zone = "3ZG7D"
    static let filledBanner = (account: "54b93", site: "2f59a", channel: "bf9bc",
                               location: "98f90072f2f1b1cd", zone: "JX5Qa")
    static let emptyBanner = (account: "ec981", site: "544fa", channel: "00000",
                              location: "greengoddess", zone: "6ambm")

    let runId = String(UUID().uuidString.prefix(6)).lowercased()
    let args = ProcessInfo.processInfo.arguments

    @Published var results: [CaseResult] = []
    @Published var prompt: String?
    @Published var running = false
    @Published var banners: [BannerSlot] = []
    @Published var showSheet = false
    @Published var status = ""

    private var promptContinuation: CheckedContinuation<Bool, Never>?
    private var bannerWaiters: [UUID: (String, Int) -> Void] = [:]
    private(set) var bannerEvents: [UUID: [String]] = [:]
    private(set) var violations: [String] = []
    private var started = Date()

    /// The long-lived instance most cases use. Created per `-benchCreate init|appear|lazy`.
    private(set) var main: SurfsideAds?
    var firstFetchAtInit: PendingFetch?
    var firstWindowAt: Date?

    var createMode: String {
        if let i = args.firstIndex(of: "-benchCreate"), args.indices.contains(i + 1) { return args[i + 1] }
        return "appear"
    }

    func user(_ suffix: String) -> String { "bench-\(runId)-\(suffix)" }

    // MARK: Instances

    func config(inspectable: Bool = true,
                userId: String? = nil,
                warm: Bool = true,
                headless: Bool = false,
                timeout: TimeInterval = 15,
                account: String = Bench.account,
                location: String = Bench.location,
                rjsURL: String = "//cdn.surfside.io/ads/2.0.0/r.js") -> SurfsideAds.Configuration {
        .init(accountId: account, siteId: Bench.site, channelId: Bench.channel, locationId: location,
              rjsURL: rjsURL, requestTimeout: timeout, isInspectable: inspectable,
              headless: headless, userId: userId, keepsPageWarm: warm)
    }

    /// Called from `App.init`, before any window exists.
    func appInit() {
        LogTap.shared.start()
        if createMode == "init" {
            main = SurfsideAds(configuration: config())
            firstFetchAtInit = begin(main!)
        }
    }

    func ensureMain() -> SurfsideAds {
        if let main = main { return main }
        let ads = SurfsideAds(configuration: config())
        main = ads
        return ads
    }

    func replaceMain() -> SurfsideAds {
        main = nil
        return ensureMain()
    }

    // MARK: Fetch

    func violation(_ text: String) {
        violations.append(text)
        NSLog("%@", "BENCH   VIOLATION: " + text)
    }

    /// Starts a fetch without holding on to `ads`, and checks the completion contract:
    /// exactly once, on the main thread, never silent.
    func begin(_ ads: SurfsideAds, zone: String = Bench.zone, maxItems: Int = 4,
               watchdog: TimeInterval = 25) -> PendingFetch {
        let pending = PendingFetch()
        let started = Date()
        ads.fetchProducts(zoneId: zone, maxItems: maxItems) { [weak self] result in
            let onMain = Thread.isMainThread
            DispatchQueue.main.async {
                if !onMain { self?.violation("completion delivered off the main thread") }
                pending.calls += 1
                if pending.calls > 1 { self?.violation("completion called \(pending.calls) times"); return }
                if pending.outcome != nil { self?.violation("completion arrived after the watchdog"); return }
                pending.complete(Outcome(result: result, ms: Int(Date().timeIntervalSince(started) * 1000)))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdog) { [weak self] in
            guard pending.outcome == nil else { return }
            self?.violation("completion never called within \(Int(watchdog))s")
            pending.complete(Outcome(result: nil, ms: Int(watchdog * 1000)))
        }
        return pending
    }

    func fetch(_ ads: SurfsideAds, zone: String = Bench.zone, maxItems: Int = 4) async -> Outcome {
        await begin(ads, zone: zone, maxItems: maxItems).wait()
    }

    func burst(_ ads: SurfsideAds, count: Int, spacing: TimeInterval,
               each: ((Int) -> Void)? = nil) async -> [Outcome] {
        var pendings: [PendingFetch] = []
        for i in 0..<count {
            each?(i)
            pendings.append(begin(ads))
            await sleep(spacing)
        }
        var outcomes: [Outcome] = []
        for pending in pendings { outcomes.append(await pending.wait()) }
        return outcomes
    }

    func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func summary(_ outcomes: [Outcome]) -> String {
        let times = outcomes.map(\.ms).sorted()
        guard !times.isEmpty else { return "none" }
        let filled = outcomes.filter(\.filled).count
        let empty = outcomes.filter { $0.succeeded && !$0.filled }.count
        let failed = outcomes.count - filled - empty
        return "\(outcomes.count) fetches: \(filled) filled, \(empty) empty, \(failed) failed; "
            + "ms min \(times.first!) median \(times[times.count / 2]) max \(times.last!)"
    }

    // MARK: Prompts (hands-on cases)

    /// Shows an instruction and waits for Continue (true) or Skip (false).
    func ask(_ text: String) async -> Bool {
        NSLog("%@", "BENCH   PROMPT: " + text)
        prompt = text
        return await withCheckedContinuation { promptContinuation = $0 }
    }

    func answer(_ proceed: Bool) {
        prompt = nil
        promptContinuation?.resume(returning: proceed)
        promptContinuation = nil
    }

    func nextNotification(_ name: Notification.Name) async {
        for await _ in NotificationCenter.default.notifications(named: name) { break }
    }

    // MARK: Hidden pages (debug hooks reach the SDK's WebViews through the view tree)

    static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    }

    static func hiddenPages() -> [WKWebView] {
        windows.flatMap { $0.subviews }.compactMap { $0 as? WKWebView }
            .filter { $0.alpha == 0 && $0.frame.origin.x < -1000 }
    }

    @discardableResult
    static func killWebContent(_ webView: WKWebView) -> Bool {
        let selector = Selector(("_killWebContentProcess"))
        guard webView.responds(to: selector) else { return false }
        webView.perform(selector)
        return true
    }

    static func memoryWarning() {
        let selector = Selector(("_performMemoryWarning"))
        if UIApplication.shared.responds(to: selector) { UIApplication.shared.perform(selector) }
    }

    // MARK: Banners

    func showBanner(_ slot: BannerSlot, watchdog: TimeInterval = 12) async -> (event: String, ms: Int) {
        let started = Date()
        banners.append(slot)
        return await withCheckedContinuation { continuation in
            var done = false
            bannerWaiters[slot.id] = { event, _ in
                guard !done else { return }
                done = true
                continuation.resume(returning: (event, Int(Date().timeIntervalSince(started) * 1000)))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + watchdog) {
                guard !done else { return }
                done = true
                continuation.resume(returning: ("NO CALLBACK", Int(watchdog * 1000)))
            }
        }
    }

    func bannerEvent(_ id: UUID, _ event: String) {
        bannerEvents[id, default: []].append(event)
        NSLog("%@", "BENCH   banner \(id.uuidString.prefix(4)) \(event)")
        bannerWaiters[id]?(event, 0)
    }

    func clearBanners() { banners.removeAll(); bannerWaiters.removeAll() }

    // MARK: Running

    func reset(_ cases: [BenchCase]) {
        results = cases.map { CaseResult(id: $0.id, title: $0.title, verdict: .pending, notes: []) }
    }

    func run(_ cases: [BenchCase]) async {
        guard !running else { return }
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        LogTap.shared.start()
        started = Date()
        for benchCase in cases {
            await runOne(benchCase)
        }
        running = false
        status = "done"
        NSLog("%@", "BENCH DONE " + tally)
    }

    var tally: String {
        let counts = Dictionary(grouping: results, by: \.verdict).mapValues(\.count)
        return [Verdict.pass, .fail, .info, .skipped, .pending]
            .compactMap { verdict in counts[verdict].map { "\($0) \(verdict.rawValue)" } }.joined(separator: ", ")
    }

    private func runOne(_ benchCase: BenchCase) async {
        guard let index = results.firstIndex(where: { $0.id == benchCase.id }) else { return }
        #if !DEBUG
        if benchCase.kind == .hook {
            results[index].verdict = .skipped
            results[index].notes = ["needs a Debug build"]
            return
        }
        #endif
        status = "\(benchCase.id) \(benchCase.title)"
        NSLog("%@", "BENCH CASE \(benchCase.id) \(benchCase.title)")
        results[index].verdict = .running
        results[index].started = Date()
        let violationsBefore = violations.count
        let ctx = Ctx(bench: self)
        await benchCase.run(ctx)
        await sleep(0.4)   // grace for a second, illegal completion call
        let newViolations = violations[violationsBefore...]
        newViolations.forEach { ctx.expect(false, "completion contract: \($0)") }
        clearBanners()
        results[index].notes = ctx.notes
        results[index].seconds = Date().timeIntervalSince(results[index].started ?? Date())
        results[index].verdict = ctx.notes.first == "skipped by tester" ? .skipped : ctx.verdict
        NSLog("%@", "BENCH RESULT \(benchCase.id) \(results[index].verdict.rawValue)")
        save()
    }

    // MARK: Results file

    static var resultsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bench-results.json")
    }

    func save() {
        #if DEBUG
        let build = "Debug"
        #else
        let build = "Release"
        #endif
        let report = BenchReport(runId: runId,
                                 device: UIDevice.current.model + " " + (Self.machine ?? ""),
                                 os: UIDevice.current.systemVersion,
                                 build: build,
                                 createMode: createMode,
                                 started: started,
                                 results: results.filter { $0.verdict != .pending })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) {
            // Keep earlier runs: one file per run id, plus "latest".
            try? data.write(to: Self.resultsURL)
            try? data.write(to: Self.resultsURL.deletingLastPathComponent()
                .appendingPathComponent("bench-results-\(runId).json"))
        }
    }

    static var machine: String? {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) }
        }
    }
}
