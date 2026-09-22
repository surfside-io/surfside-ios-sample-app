//
//  BenchCases.swift
//  AdsKit Test Bench: one entry per row of adskit-device-test-plan.md.
//  Cases that can only be judged from production data (B8, C1, C2 counts) log what to
//  look for and are checked afterwards from the bid log and surf_events.
//

import SwiftUI
import UIKit
import WebKit
import SurfsideTracker
#if DEBUG
@testable import SurfsideAdsKit
#else
import SurfsideAdsKit
#endif

#if DEBUG
final class BenchIdentity: IdentityProvider {
    var id: String?
    func domainUserId() -> String? { id }
}
#endif

private extension Array where Element == String {
    func count(containing text: String) -> Int { filter { $0.contains(text) }.count }
}

@MainActor
enum BenchCases {

    static var all: [BenchCase] { fetchCases + identityCases + trackingCases + lifecycleCases
        + instanceCases + networkCases + windowCases + bannerCases + buildCases + orderCases }

    private static var tap: LogTap { LogTap.shared }

    /// Run a short fetch series under a condition the tester sets up by hand.
    private static func conditionRun(_ ctx: Ctx, setUp: String, restore: String?, fetches: Int = 8) async {
        let bench = ctx.bench
        guard await bench.ask(setUp) else { ctx.note("skipped by tester"); return }
        let ads = bench.ensureMain()
        let outcomes = await bench.burst(ads, count: fetches, spacing: 0.5)
        ctx.note(bench.summary(outcomes))
        ctx.expect(outcomes.allSatisfy { $0.result != nil }, "every fetch resolved")
        ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed")
        if let restore = restore { _ = await bench.ask(restore) }
    }

    // MARK: A. Fetch outcomes

    static let fetchCases: [BenchCase] = [
        BenchCase(id: "A1", title: "Filled zone, warm page, 20 in a row (and B3: no reloads)", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            let warmUp = await bench.fetch(ads)
            ctx.note("first: " + warmUp.text)
            let mark = tap.mark()
            var outcomes: [Outcome] = []
            for _ in 0..<20 { outcomes.append(await bench.fetch(ads)) }
            ctx.note(bench.summary(outcomes))
            ctx.expectFilled(outcomes, "all 20 filled")
            ctx.expect((outcomes.map(\.ms).max() ?? 0) < 1000, "none over 1s")
            ctx.expectLog(tap.since(mark).count(containing: "page: loading") == 0, "no page reload during the series")
        },
        BenchCase(id: "A2", title: "Fetch issued in App.init, before any window", kind: .auto) { ctx in
            let bench = ctx.bench
            guard let first = bench.firstFetchAtInit else {
                ctx.note("not this launch: relaunch with -benchCreate init"); ctx.infoOnly(); return
            }
            let outcome = await first.wait()
            ctx.note("fetch from App.init: " + outcome.text)
            if let window = bench.firstWindowAt {
                ctx.note("first window \(Int(window.timeIntervalSince(Bench.processStart) * 1000))ms after process start")
            }
            ctx.expect(outcome.filled, "filled")
        },
        BenchCase(id: "A3", title: "No fill (random location)", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = SurfsideAds(configuration: bench.config(location: UUID().uuidString.lowercased()))
            await bench.sleep(1.5)
            let first = await bench.fetch(ads), second = await bench.fetch(ads)
            ctx.note("first \(first.text), warm \(second.text)")
            ctx.expect(first.succeeded && !first.filled, "first returns []")
            ctx.expect(second.succeeded && !second.filled, "second returns []")
            ctx.expect(first.ms < 3000 && second.ms < 1500, "no ceiling wait")
        },
        BenchCase(id: "A4", title: "Wrong account id, wrong zone id", kind: .auto) { ctx in
            let bench = ctx.bench
            let wrongAccount = SurfsideAds(configuration: bench.config(account: "zzzzz"))
            await bench.sleep(1.5)
            let a = await bench.fetch(wrongAccount)
            ctx.note("wrong account: " + a.text)
            let main = bench.ensureMain()
            let z = await bench.fetch(main, zone: "ZZZZZ")
            ctx.note("wrong zone: " + z.text)
            let good = await bench.fetch(main)
            ctx.note("good fetch after: " + good.text)
            ctx.expect(a.result != nil && z.result != nil, "both resolved")
            ctx.expect(a.ms < 10500 && z.ms < 10500, "neither waited past the 8s ceiling (plus WebView start on the one-shot path)")
            ctx.expect(good.filled, "page still serves a good fetch")
        },
        BenchCase(id: "A5", title: "maxItems 1, 4, 10, 20, 50", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            for n in [1, 4, 10, 20, 50] {
                let outcome = await bench.fetch(ads, maxItems: n)
                ctx.note("maxItems \(n): " + outcome.text)
                ctx.expect(outcome.filled && outcome.products.count <= n, "maxItems \(n): 1...\(n) products")
            }
        },
        BenchCase(id: "A6", title: "Three fetches at once, different maxItems (cross-talk check)", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            let sizes = [1, 3, 6]
            let pendings = sizes.map { bench.begin(ads, maxItems: $0) }
            for (n, pending) in zip(sizes, pendings) {
                let outcome = await pending.wait()
                ctx.note("maxItems \(n): " + outcome.text)
                ctx.expect(outcome.filled && outcome.products.count <= n, "caller \(n) got its own result")
            }
            ctx.note("A cross-talk would show as a caller receiving more products than it asked for.")
        },
        BenchCase(id: "A7", title: "Same zone twice at once", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            let a = bench.begin(ads), b = bench.begin(ads)
            let (ra, rb) = (await a.wait(), await b.wait())
            ctx.note("\(ra.text) and \(rb.text)")
            ctx.expect(ra.filled && rb.filled, "both filled")
        },
        BenchCase(id: "A8", title: "Burst: 40 fetches at 80ms spacing", kind: .auto) { ctx in
            let bench = ctx.bench
            let outcomes = await bench.burst(bench.ensureMain(), count: 40, spacing: 0.08)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy { $0.result != nil }, "all resolved")
            ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed")
        },
        BenchCase(id: "A9", title: "requestTimeout shorter than the fetch", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = SurfsideAds(configuration: bench.config(timeout: 0.03))
            await bench.sleep(1.5)
            let first = await bench.fetch(ads)
            await bench.sleep(1.0)   // let the page's late answer arrive and be dropped
            let second = await bench.fetch(ads)
            ctx.note("\(first.text), then \(second.text)")
            ctx.expect(!first.succeeded && first.result != nil, "first times out")
            ctx.expect(second.result != nil, "second resolves (the page survived the dropped answer)")
        },
        BenchCase(id: "A10", title: "Undecodable payload for a live fetch", kind: .hook) { ctx in
            let bench = ctx.bench
            let before = Set(Bench.hiddenPages().map(ObjectIdentifier.init))
            let ads = SurfsideAds(configuration: bench.config())
            await bench.sleep(1.5)
            guard let page = Bench.hiddenPages().first(where: { !before.contains(ObjectIdentifier($0)) }) else {
                ctx.expect(false, "found the instance's hidden page"); return
            }
            let pending = bench.begin(ads)
            let js = """
            (function () {
              var el = document.querySelector('surf-carousel');
              if (!el) return 'no element';
              var id = el.id.replace('surf-fetch-', '');
              window.webkit.messageHandlers.surfsidePage.postMessage(
                JSON.stringify({ id: id, status: 'ok', products: 'not an array' }));
              return id;
            })()
            """
            let injected = try? await page.evaluateJavaScript(js)
            let outcome = await pending.wait()
            ctx.note("injected for fetch \(injected ?? "?"): " + outcome.text)
            ctx.expect("\(outcome.text)".contains("decodeFailed"), "fails with decodeFailed")
            ctx.expect(outcome.ms < 1000, "fails at once, not at the 15s timeout")
            let next = await bench.fetch(ads)
            ctx.expect(next.filled, "next fetch fine: " + next.text)
        },
    ]

    // MARK: B. Identity

    static let identityCases: [BenchCase] = [
        BenchCase(id: "B1", title: "Anonymous, A, B, anonymous (and B2: \"\" equals nil)", kind: .hook) { ctx in
            #if DEBUG
            let bench = ctx.bench
            let identity = BenchIdentity()
            let ads = SurfsideAds(configuration: bench.config(), identityProvider: identity)
            await bench.sleep(1.5)
            let phases: [(String?, String)] = [(nil, "anonymous"), (bench.user("A"), "A"), (bench.user("B"), "B"),
                                                ("", "empty string"), (nil, "nil again")]
            var reloads = 0
            for (id, label) in phases {
                identity.id = id
                let mark = tap.mark()
                let first = await bench.fetch(ads), second = await bench.fetch(ads)
                let lines = tap.since(mark)
                let users = Set(LogTap.initUsers(lines, account: Bench.account))
                reloads += lines.count(containing: "identity changed")
                ctx.note("\(label): \(first.text), \(second.text); web SDK initialised with \(users.sorted())")
                ctx.expect(first.filled && second.filled, "\(label): both filled")
                ctx.expectLog(users == [id ?? ""], "\(label): web SDK saw only this identity")
            }
            ctx.expectLog(reloads == 3, "3 identity reloads (to A, to B, to anonymous), none between \"\" and nil; saw \(reloads)")
            #endif
        },
        BenchCase(id: "B4", title: "Identity change while fetches are in flight", kind: .hook) { ctx in
            #if DEBUG
            let bench = ctx.bench
            let identity = BenchIdentity()
            identity.id = bench.user("C")
            let ads = SurfsideAds(configuration: bench.config(), identityProvider: identity)
            await bench.sleep(1.5)
            _ = await bench.fetch(ads)
            let mark = tap.mark()
            let outcomes = await bench.burst(ads, count: 12, spacing: 0.04) { i in
                if i == 6 { identity.id = bench.user("D") }
            }
            let lines = tap.since(mark)
            ctx.note(bench.summary(outcomes))
            ctx.expectFilled(outcomes, "all 12 filled")
            ctx.expectLog(lines.count(containing: "identity changed") == 1, "exactly one identity reload")
            let users = LogTap.initUsers(lines, account: Bench.account)
            let firstD = users.firstIndex(of: bench.user("D")) ?? users.count
            ctx.expectLog(!users[firstD...].contains(bench.user("C")), "no fetch ran as C after the first D")
            #endif
        },
        BenchCase(id: "B5", title: "Tracker identity on the main instance (B7: late cookie seed)", kind: .auto) { ctx in
            let bench = ctx.bench
            let all = tap.since(0)
            let users = LogTap.initUsers(all, account: Bench.account).filter { !$0.hasPrefix("bench-") }
            ctx.note("main instance has initialised the web SDK with: \(Set(users).sorted())")
            ctx.note("identity reloads so far: \(all.count(containing: "identity changed")), late cookie seeds: \(all.count(containing: "landed late"))")
            let outcome = await bench.fetch(bench.ensureMain())
            ctx.expect(outcome.filled, "fetch fine: " + outcome.text)
            ctx.infoOnly()
        },
        BenchCase(id: "B6", title: "Explicit Configuration.userId", kind: .auto) { ctx in
            let bench = ctx.bench
            let explicit = bench.user("explicit")
            let ads = SurfsideAds(configuration: bench.config(userId: explicit))
            let mark = tap.mark()
            let outcome = await bench.fetch(ads)
            let users = Set(LogTap.initUsers(tap.since(mark), account: Bench.account))
            ctx.note("\(outcome.text); web SDK initialised with \(users.sorted())")
            ctx.expect(outcome.filled, "filled")
            ctx.expectLog(users == [explicit], "explicit id is the one used")
        },
    ]

    // MARK: C. Tracking

    static let trackingCases: [BenchCase] = [
        BenchCase(id: "C2", title: "recordImpression and recordClick (C3 twice, C5 after release)", kind: .auto) { ctx in
            let bench = ctx.bench
            let user = bench.user("track")
            var ads: SurfsideAds? = SurfsideAds(configuration: bench.config(userId: user))
            let outcome = await bench.fetch(ads!)
            ctx.expect(outcome.filled, "fetched: " + outcome.text)
            let products = outcome.products
            ads = nil                               // C5: the page these came from is gone
            await bench.sleep(0.5)
            let recorder = bench.ensureMain()
            var fired = 0
            for product in products {
                let ok: Bool = await withCheckedContinuation { c in recorder.recordImpression(product) { c.resume(returning: $0) } }
                if ok { fired += 1 }
            }
            ctx.expect(fired == products.count, "recordImpression succeeded for \(fired) of \(products.count)")
            if let first = products.first {
                let again: Bool = await withCheckedContinuation { c in recorder.recordImpression(first) { c.resume(returning: $0) } }
                let click: Bool = await withCheckedContinuation { c in recorder.recordClick(first) { c.resume(returning: $0) } }
                ctx.note("C3 second recordImpression for product \(first.id): \(again); recordClick: \(click)")
            }
            // Only sponsored cards carry trackers; organic recommendations in a hybrid carousel have none.
            let tracked = products.filter { !$0.winTrackerURLs.isEmpty || !$0.impressionTrackerURLs.isEmpty }
            ctx.note("\(tracked.count) of \(products.count) products carry trackers (sponsored): \(tracked.map(\.id)); first product tracked: \(products.first.map { p in tracked.contains { $0.id == p.id } } ?? false)")
            ctx.note("CHECK IN surf_events at \(ISO8601DateFormatter().string(from: Date())) UTC, user \(user): expect \(tracked.count) wins + \(tracked.count) impressions (+1 each if the first product is tracked and C3 is not deduped), 1 click if the first product is tracked; products \(products.map(\.id))")
        },
    ]

    // MARK: D. App lifecycle

    static let lifecycleCases: [BenchCase] = [
        BenchCase(id: "D1", title: "Background while idle, then foreground", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            guard await bench.ask("Tap Continue, then go to the Home Screen, wait 5 seconds, and come back.") else { ctx.note("skipped by tester"); return }
            let mark = tap.mark()
            await bench.nextNotification(UIApplication.willEnterForegroundNotification)
            await bench.sleep(1.5)
            let lines = tap.since(mark)
            ctx.expectLog(lines.count(containing: "released (app entered background)") >= 1, "page released in the background")
            ctx.expectLog(lines.count(containing: "loading (warm up)") >= 1, "page re-warmed on foreground")
            let outcome = await bench.fetch(ads)
            ctx.expect(outcome.filled && outcome.ms < 1000, "next fetch: " + outcome.text)
        },
        BenchCase(id: "D2", title: "Background in the middle of a burst", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            guard await bench.ask("Tap Continue. A 6 second burst starts: go to the Home Screen right away, wait 10 seconds, come back.") else { ctx.note("skipped by tester"); return }
            let mark = tap.mark()
            let outcomes = await bench.burst(ads, count: 60, spacing: 0.1)
            await bench.sleep(1.0)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy { $0.result != nil }, "every fetch resolved (filled or timeout, never silent)")
            ctx.expectLog(tap.since(mark).count(containing: "released (app") >= 1, "page released once the fetches finished")
            let after = await bench.fetch(ads)
            ctx.expect(after.filled, "fetch after return: " + after.text)
        },
        BenchCase(id: "D3", title: "Fetch issued while already in the background", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            guard await bench.ask("Tap Continue, go to the Home Screen within 5 seconds, wait 10 seconds, come back.") else { ctx.note("skipped by tester"); return }
            let mark = tap.mark()
            await bench.nextNotification(UIApplication.didEnterBackgroundNotification)
            let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            await bench.sleep(1.0)
            let outcome = await bench.fetch(ads)
            await bench.sleep(0.5)
            UIApplication.shared.endBackgroundTask(task)
            ctx.note("background fetch: " + outcome.text)
            ctx.expect(outcome.result != nil, "resolved")
            ctx.expectLog(tap.since(mark).count(containing: "released (app is in the background)") >= 1, "page released again afterwards")
        },
        BenchCase(id: "D4", title: "15 minutes in the background", kind: .hands, long: true) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            guard await bench.ask("LONG: Tap Continue, leave the app in the background for 15 minutes, come back.") else { ctx.note("skipped by tester"); return }
            let left = Date()
            await bench.nextNotification(UIApplication.willEnterForegroundNotification)
            await bench.sleep(1.5)
            let outcome = await bench.fetch(ads)
            ctx.note("away \(Int(Date().timeIntervalSince(left)))s; " + outcome.text)
            ctx.expect(outcome.filled, "filled after the long background")
        },
        BenchCase(id: "D5", title: "Control Centre and Notification Centre (resign active only)", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            let mark = tap.mark()
            var backgrounded = 0, resigned = 0
            let center = NotificationCenter.default
            let observers = [
                center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in backgrounded += 1 },
                center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in resigned += 1 },
            ]
            defer { observers.forEach(center.removeObserver) }
            guard await bench.ask("Do NOT lock the phone or leave the app. Open Control Centre and close it. Pull down Notification Centre and close it. Then tap Continue.") else { ctx.note("skipped by tester"); return }
            let released = tap.since(mark).filter { $0.contains("released") }.compactMap { $0.components(separatedBy: "page: ").last }
            ctx.note("iOS sent willResignActive \(resigned)x, didEnterBackground \(backgrounded)x; page log: \(released)")
            if backgrounded > 0 {
                ctx.note("iOS itself put the app in the background, so releasing the page was correct")
                ctx.infoOnly()
            } else {
                ctx.expectLog(released.isEmpty, "nothing released on resign active alone")
            }
            let outcome = await bench.fetch(ads)
            ctx.expectFilled([outcome], "next fetch: " + outcome.text)
        },
        BenchCase(id: "D6", title: "Memory warning, idle and mid-burst", kind: .hook) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            var mark = tap.mark()
            Bench.memoryWarning()
            await bench.sleep(0.5)
            ctx.expectLog(tap.since(mark).count(containing: "released (memory warning)") == 1, "idle: released at once")
            let rebuilt = await bench.fetch(ads)
            ctx.expect(rebuilt.filled, "idle: next fetch rebuilds: " + rebuilt.text)

            mark = tap.mark()
            let pendings = (0..<8).map { _ in bench.begin(ads) }
            Bench.memoryWarning()
            var outcomes: [Outcome] = []
            for pending in pendings { outcomes.append(await pending.wait()) }
            await bench.sleep(0.5)
            ctx.note("busy: " + bench.summary(outcomes))
            ctx.expectFilled(outcomes, "busy: no fetch lost")
            ctx.expectLog(tap.since(mark).count(containing: "released (memory warning)") == 1, "busy: released when the fetches finished")
            let after = await bench.fetch(ads)
            ctx.expect(after.filled, "busy: next fetch rebuilds: " + after.text)
        },
        BenchCase(id: "D7", title: "Web content process killed while idle", kind: .hook) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            let pages = Bench.hiddenPages()
            ctx.expect(pages.count == 1, "exactly one hidden page alive (found \(pages.count))")
            let mark = tap.mark()
            ctx.expect(pages.first.map(Bench.killWebContent) ?? false, "kill hook available")
            await bench.sleep(1.0)
            ctx.expectLog(tap.since(mark).count(containing: "web content process ended") == 1, "death detected")
            let outcome = await bench.fetch(ads)
            ctx.expect(outcome.filled, "next fetch rebuilds the page: " + outcome.text)
        },
        BenchCase(id: "D8", title: "Killed with fetches in flight", kind: .hook) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            let mark = tap.mark()
            var pendings: [PendingFetch] = []
            for i in 0..<12 {
                pendings.append(bench.begin(ads))
                if i == 4 { Bench.hiddenPages().first.map { _ = Bench.killWebContent($0) } }
                await bench.sleep(0.03)
            }
            var outcomes: [Outcome] = []
            for pending in pendings { outcomes.append(await pending.wait()) }
            let ended = tap.since(mark).first { $0.contains("web content process ended") } ?? "not logged"
            ctx.note(bench.summary(outcomes) + "; " + (ended.components(separatedBy: "page: ").last ?? ""))
            ctx.expectFilled(outcomes, "none lost")
        },
        BenchCase(id: "D9", title: "Killed twice during the same fetch", kind: .hook) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            let mark = tap.mark()
            let pending = bench.begin(ads)
            Bench.hiddenPages().first.map { _ = Bench.killWebContent($0) }
            let rebuilt = await tap.wait(for: "ready in", after: mark, timeout: 5)
            Bench.hiddenPages().first.map { _ = Bench.killWebContent($0) }
            let outcome = await pending.wait()
            ctx.note("rebuilt seen: \(rebuilt); doubly interrupted fetch: " + outcome.text)
            if outcome.filled {
                ctx.note("the second kill landed too late to interrupt it; not a failure")
                ctx.infoOnly()
            } else {
                ctx.expect(outcome.result != nil && outcome.ms < 5000, "fails once and promptly")
            }
            let next = await bench.fetch(ads)
            ctx.expect(next.filled, "later fetch fine: " + next.text)
        },
        BenchCase(id: "D10", title: "Recycle at the real threshold (120 fetches)", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.replaceMain()
            await bench.sleep(1.5)
            let mark = tap.mark()
            var outcomes: [Outcome] = []
            for _ in 0..<120 { outcomes.append(await bench.fetch(ads)) }
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed")
            ctx.expect(outcomes.filter(\.filled).count >= 118, "at most 2 genuine no-bids")
            ctx.expectLog(tap.since(mark).count(containing: "recycle after 50 fetches") == 2, "recycled at 50 and at 100")
        },
        BenchCase(id: "D11", title: "Recycle by time (threshold shrunk to 10s)", kind: .hook) { ctx in
            #if DEBUG
            let bench = ctx.bench
            let ads = bench.replaceMain()
            await bench.sleep(1.5)
            let warm = await bench.fetch(ads)
            ctx.note("warm: " + warm.text)
            let saved = CarouselPage.recycleAfterSeconds
            CarouselPage.recycleAfterSeconds = 10
            defer { CarouselPage.recycleAfterSeconds = saved }
            let early = await bench.fetch(ads)
            ctx.note("at once: " + early.text)
            await bench.sleep(11)
            let mark = tap.mark()
            let late = await bench.fetch(ads)
            ctx.note("after 11s: " + late.text)
            let lines = tap.since(mark)
            ctx.expect(warm.filled && early.filled && late.filled, "all three filled")
            ctx.expectLog(lines.count(containing: "recycle after") == 1, "the fetch after the threshold recycled the page")
            ctx.note("page log: " + lines.filter { $0.contains("page:") }.map { String($0.suffix(70)) }.joined(separator: " | "))
            #else
            ctx.note("needs a Debug build")
            #endif
        },
        BenchCase(id: "D12", title: "Low Power Mode", kind: .hands) { ctx in
            await conditionRun(ctx, setUp: "Turn ON Low Power Mode (Settings, Battery), come back and tap Continue.",
                               restore: "Turn Low Power Mode OFF again, then tap Continue.")
        },
    ]

    // MARK: E. Instance lifecycle

    static let instanceCases: [BenchCase] = [
        BenchCase(id: "E1", title: "Where the instance was created this launch", kind: .auto) { ctx in
            let bench = ctx.bench
            ctx.note("create mode: \(bench.createMode) (relaunch with -benchCreate init|appear|lazy for the others)")
            let outcome = await bench.fetch(bench.ensureMain())
            ctx.expect(outcome.filled, outcome.text)
        },
        BenchCase(id: "E2", title: "Instance created on a background thread", kind: .auto) { ctx in
            let bench = ctx.bench
            let configuration = bench.config()
            let ads = await Task.detached { SurfsideAds(configuration: configuration) }.value
            await bench.sleep(1.5)
            let outcome = await bench.fetch(ads)
            ctx.expect(outcome.filled && outcome.ms < 1500, "warm and filled: " + outcome.text)
        },
        BenchCase(id: "E3", title: "Released while idle, on main and off main", kind: .auto) { ctx in
            let bench = ctx.bench
            let baseline = Bench.hiddenPages().count
            for offMain in [false, true] {
                var ads: SurfsideAds? = SurfsideAds(configuration: bench.config())
                _ = await bench.fetch(ads!)
                ctx.expect(Bench.hiddenPages().count == baseline + 1, "page exists (offMain \(offMain))")
                if offMain {
                    let held = ads; ads = nil
                    await Task.detached { _ = held }.value
                } else {
                    ads = nil
                }
                await bench.sleep(0.5)
                ctx.expect(Bench.hiddenPages().count == baseline, "page gone after release (offMain \(offMain))")
            }
        },
        BenchCase(id: "E4", title: "Released mid-fetch, on main and off main", kind: .auto) { ctx in
            let bench = ctx.bench
            let baseline = Bench.hiddenPages().count
            for offMain in [false, true] {
                var ads: SurfsideAds? = SurfsideAds(configuration: bench.config())
                await bench.sleep(1.0)
                let pending = bench.begin(ads!)
                if offMain {
                    let held = ads; ads = nil
                    Task.detached { _ = held }
                } else {
                    ads = nil
                }
                let outcome = await pending.wait()
                ctx.note("offMain \(offMain): " + outcome.text)
                ctx.expectFilled([outcome], "the fetch still delivers, as in 1.0.0 (offMain \(offMain))")
                await bench.sleep(0.5)
                ctx.expect(Bench.hiddenPages().count == baseline, "its page is gone once the fetch resolved (offMain \(offMain))")
            }
        },
        BenchCase(id: "E10", title: "Throwaway instance: SurfsideAds(...).fetchProducts, never retained", kind: .auto) { ctx in
            let bench = ctx.bench
            let baseline = Bench.hiddenPages().count
            var outcomes: [Outcome] = []
            for _ in 0..<3 {
                outcomes.append(await bench.begin(SurfsideAds(configuration: bench.config())).wait())
            }
            ctx.note(bench.summary(outcomes))
            ctx.expectFilled(outcomes, "works without holding the instance, as in 1.0.0")
            await bench.sleep(0.5)
            ctx.expect(Bench.hiddenPages().count == baseline, "no page left behind")
        },
        BenchCase(id: "E5", title: "Create and release 30 instances", kind: .auto) { ctx in
            let bench = ctx.bench
            let baseline = Bench.hiddenPages().count
            for i in 0..<30 {
                var ads: SurfsideAds? = SurfsideAds(configuration: bench.config())
                if i % 3 == 0 { _ = await bench.fetch(ads!) } else { await bench.sleep(0.25) }
                ads = nil
            }
            await bench.sleep(1.0)
            ctx.expect(Bench.hiddenPages().count == baseline, "hidden pages back to \(baseline) (now \(Bench.hiddenPages().count))")
            let outcome = await bench.fetch(bench.ensureMain())
            ctx.expect(outcome.filled, "main instance unaffected: " + outcome.text)
        },
        BenchCase(id: "E6", title: "Two instances with different users", kind: .auto) { ctx in
            let bench = ctx.bench
            let x = SurfsideAds(configuration: bench.config(userId: bench.user("X")))
            let y = SurfsideAds(configuration: bench.config(userId: bench.user("Y")))
            await bench.sleep(1.5)
            let mark = tap.mark()
            let px = (0..<4).map { _ in bench.begin(x) }, py = (0..<4).map { _ in bench.begin(y) }
            var outcomes: [Outcome] = []
            for pending in px + py { outcomes.append(await pending.wait()) }
            let users = LogTap.initUsers(tap.since(mark), account: Bench.account)
            ctx.note(bench.summary(outcomes))
            ctx.expectFilled(outcomes, "all filled")
            ctx.expectLog(Set(users) == [bench.user("X"), bench.user("Y")], "both users seen, nobody else: \(Set(users).sorted())")
            ctx.note("CHECK IN bid log: X and Y each on exactly 4 requests.")
        },
        BenchCase(id: "E7", title: "keepsPageWarm: false (one-shot path)", kind: .auto) { ctx in
            let bench = ctx.bench
            let baseline = Bench.hiddenPages().count
            let ads = SurfsideAds(configuration: bench.config(warm: false))
            var outcomes: [Outcome] = []
            for _ in 0..<6 { outcomes.append(await bench.fetch(ads)) }
            ctx.note(bench.summary(outcomes))
            ctx.expectFilled(outcomes, "all filled")
            ctx.expect(Bench.hiddenPages().count == baseline, "no persistent page was created")
            let empty = await bench.fetch(SurfsideAds(configuration: bench.config(warm: false, location: UUID().uuidString.lowercased())))
            ctx.expect(empty.succeeded && !empty.filled && empty.ms < 3000, "one-shot no fill: " + empty.text)
        },
        BenchCase(id: "E8", title: "headless: true", kind: .auto) { ctx in
            let bench = ctx.bench
            let outcome = await bench.fetch(SurfsideAds(configuration: bench.config(headless: true)))
            ctx.note(outcome.text)
            ctx.expect(outcome.result != nil, "resolved")
            ctx.infoOnly()
        },
        BenchCase(id: "E9", title: "isInspectable: false (the shipping config)", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = SurfsideAds(configuration: bench.config(inspectable: false))
            await bench.sleep(1.5)
            let mark = tap.mark()
            var outcomes: [Outcome] = []
            for _ in 0..<10 { outcomes.append(await bench.fetch(ads)) }
            let empty = await bench.fetch(SurfsideAds(configuration: bench.config(inspectable: false, location: UUID().uuidString.lowercased())))
            ctx.note(bench.summary(outcomes) + "; no fill: " + empty.text)
            ctx.expectFilled(outcomes, "all filled")
            ctx.expect(empty.succeeded && !empty.filled && empty.ms < 3000, "no fill is fast")
            ctx.expectLog(tap.since(mark).isEmpty, "the SDK logged nothing (\(tap.since(mark).count) lines)")
        },
    ]

    // MARK: F. Network

    static let networkCases: [BenchCase] = [
        BenchCase(id: "F1", title: "Offline at first load, then network back", kind: .hands) { ctx in
            let bench = ctx.bench
            guard await bench.ask("Turn ON Airplane Mode and make sure Wi-Fi is off too. Come back and tap Continue.") else { ctx.note("skipped by tester"); return }
            let ads = SurfsideAds(configuration: bench.config())
            await bench.sleep(1.0)
            let offline = await bench.fetch(ads)
            ctx.note("offline: " + offline.text)
            ctx.expect(offline.result != nil && !offline.filled, "does not fill offline")
            ctx.expect(offline.ms < 4000, "fails fast, not at the 8s ceiling or the 15s timeout")
            _ = await bench.ask("Turn Airplane Mode OFF, wait until you are online, then tap Continue.")
            let online = await bench.fetch(ads)
            ctx.expect(online.filled, "same instance recovers with no restart: " + online.text)
        },
        BenchCase(id: "F2", title: "Offline after the page is warm", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            guard await bench.ask("Turn ON Airplane Mode (Wi-Fi off too). Come back and tap Continue.") else { ctx.note("skipped by tester"); return }
            let offline = await bench.fetch(ads)
            ctx.note("offline on a warm page: " + offline.text)
            ctx.expect(offline.result != nil && offline.ms < 9500, "resolves within the ceiling")
            _ = await bench.ask("Turn Airplane Mode OFF, wait until you are online, then tap Continue.")
            let online = await bench.fetch(ads)
            ctx.expect(online.filled, "recovers: " + online.text)
        },
        BenchCase(id: "F3", title: "Network Link Conditioner: Very Bad Network", kind: .hands) { ctx in
            let bench = ctx.bench
            guard await bench.ask("Settings, Developer, Network Link Conditioner: choose Very Bad Network and enable it. Come back and tap Continue.") else { ctx.note("skipped by tester"); return }
            let ads = SurfsideAds(configuration: bench.config())
            let outcomes = await bench.burst(ads, count: 6, spacing: 1.0)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy { $0.result != nil && $0.ms < 16500 }, "all resolve within requestTimeout")
            _ = await bench.ask("Disable the Network Link Conditioner, then tap Continue.")
            let after = await bench.fetch(ads)
            ctx.expect(after.filled, "fine afterwards: " + after.text)
        },
        BenchCase(id: "F4", title: "100% loss mid-burst", kind: .hands) { ctx in
            let bench = ctx.bench
            guard await bench.ask("Set Network Link Conditioner to 100% Loss but do NOT enable it yet. Tap Continue, then enable it within 3 seconds (a 10 second burst runs). Come back when you are done.") else { ctx.note("skipped by tester"); return }
            let ads = bench.ensureMain()
            let outcomes = await bench.burst(ads, count: 40, spacing: 0.25)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy { $0.result != nil }, "all resolved")
            _ = await bench.ask("Disable the Network Link Conditioner, then tap Continue.")
            let after = await bench.fetch(ads)
            ctx.expect(after.filled, "page usable afterwards: " + after.text)
        },
        BenchCase(id: "F5", title: "Wi-Fi to cellular handoff mid-burst", kind: .hands) { ctx in
            let bench = ctx.bench
            guard await bench.ask("Be on Wi-Fi with cellular data on. Tap Continue, then turn Wi-Fi OFF in Control Centre within 3 seconds (a 10 second burst runs).") else { ctx.note("skipped by tester"); return }
            let outcomes = await bench.burst(bench.ensureMain(), count: 40, spacing: 0.25)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy { $0.result != nil }, "all resolved")
            ctx.expectFilled(Array(outcomes.suffix(10)), "the last 10 (on cellular) filled")
            _ = await bench.ask("Turn Wi-Fi back on, then tap Continue.")
        },
        BenchCase(id: "F6", title: "r.js URL that does not load", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = SurfsideAds(configuration: bench.config(rjsURL: "//cdn.surfside.io/ads/2.0.0/does-not-exist.js"))
            await bench.sleep(1.5)
            let mark = tap.mark()
            let outcome = await bench.fetch(ads)
            ctx.note(outcome.text)
            ctx.expect("\(outcome.text)".contains("loadFailed"), "fails with loadFailed")
            ctx.expect(outcome.ms < 3000, "fails fast")
            ctx.expectLog(tap.since(mark).count(containing: "ad SDK missing from the page, 1 in flight") == 2, "one retry only")
        },
        BenchCase(id: "F7", title: "VPN or DNS ad blocker on the phone (optional)", kind: .hands) { ctx in
            let bench = ctx.bench
            guard await bench.ask("OPTIONAL: enable a VPN or DNS content blocker that blocks ad hosts, then tap Continue. Skip if you have none.") else { ctx.note("skipped by tester"); return }
            let ads = SurfsideAds(configuration: bench.config())
            let outcomes = await bench.burst(ads, count: 4, spacing: 0.5)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy { $0.result != nil && $0.ms < 16500 }, "resolves cleanly, no hang")
            _ = await bench.ask("Turn it off again, then tap Continue.")
            ctx.infoOnly()
        },
        BenchCase(id: "F8", title: "Lockdown Mode (optional, restarts the phone)", kind: .hands, long: true) { ctx in
            await conditionRun(ctx, setUp: "OPTIONAL and slow: with Lockdown Mode on, tap Continue. Skip otherwise.", restore: nil)
        },
    ]

    // MARK: G. Windows

    static let windowCases: [BenchCase] = [
        BenchCase(id: "G1", title: "Page hosted in a window that goes away (G2: transient key window)", kind: .auto) { ctx in
            let bench = ctx.bench
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let original = scene.windows.first(where: \.isKeyWindow) else {
                ctx.expect(false, "found the app's key window"); return
            }
            var temporary: UIWindow? = UIWindow(windowScene: scene)
            temporary?.rootViewController = UIViewController()
            temporary?.windowLevel = .alert
            temporary?.makeKeyAndVisible()
            let ads = SurfsideAds(configuration: bench.config())
            await bench.sleep(2.0)
            let hostedThere = temporary?.subviews.contains { $0 is WKWebView } ?? false
            ctx.expect(hostedThere, "the page was hosted in the transient key window")
            let warm = await bench.fetch(ads)
            ctx.expect(warm.filled, "serves from there: " + warm.text)
            temporary?.isHidden = true
            temporary?.windowScene = nil
            temporary = nil
            original.makeKey()
            await bench.sleep(0.5)
            let mark = tap.mark()
            let outcome = await bench.fetch(ads)
            ctx.expect(outcome.filled && outcome.ms < 3000, "fetch after the window went away: " + outcome.text)
            ctx.expectLog(tap.since(mark).count(containing: "host window went away,") == 1, "rebuilt in a live window")
        },
        BenchCase(id: "G3", title: "Sheet presented during fetches", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            bench.showSheet = true
            await bench.sleep(0.8)
            let during = await bench.burst(ads, count: 5, spacing: 0.1)
            bench.showSheet = false
            await bench.sleep(0.8)
            let after = await bench.burst(ads, count: 5, spacing: 0.1)
            ctx.note("during: " + bench.summary(during)); ctx.note("after: " + bench.summary(after))
            ctx.expectFilled((during + after), "all filled")
        },
        BenchCase(id: "G4", title: "Rotation", kind: .hands) { ctx in
            await conditionRun(ctx, setUp: "Tap Continue, then rotate the phone back and forth for 5 seconds (rotation lock off).", restore: nil)
        },
        BenchCase(id: "G5", title: "iPad: second window, close the one hosting the page", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            let warm = await bench.fetch(ads)
            ctx.note("page warmed in this window: " + warm.text)
            guard await bench.ask("iPad only. Open a second window of this app (long-press the Dock icon, Show All Windows, +, or drag the icon to the side), then close THIS window from the app switcher. In the surviving window, open Test Bench and tap Continue.") else {
                ctx.note("skipped by tester"); return
            }
            let mark = tap.mark()
            let outcomes = await bench.burst(ads, count: 5, spacing: 0.5)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed")
            ctx.expectFilled(outcomes, "all filled in the surviving window")
            ctx.note("page log since Continue: " + tap.since(mark).filter { $0.contains("page:") }.map { String($0.suffix(80)) }.joined(separator: " | "))
        },
        BenchCase(id: "G6", title: "iPad: Split View resize and Stage Manager", kind: .hands) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            guard await bench.ask("iPad only. Tap Continue, then for about 10 seconds resize the window (Split View divider or Stage Manager corner drag), and switch between windows if Stage Manager is on.") else {
                ctx.note("skipped by tester"); return
            }
            let outcomes = await bench.burst(ads, count: 20, spacing: 0.5)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed while resizing")
            ctx.expectFilled(outcomes, "all filled")
        },
        // Programmatic forms of G6 and G5 for a simulator with nobody at the screen. The scene
        // requests are the calls the system makes for the Dock and the app switcher: opening a
        // second scene beside the hosting one puts both in Split View (a real resize of the
        // hosting window), closing it gives the width back. A divider drag has no API, and an
        // iPad app that supports multitasking may not request an orientation.
        BenchCase(id: "G6a", title: "iPad: Split View opened and closed beside the page under fetches", kind: .auto) { ctx in
            let bench = ctx.bench
            let app = UIApplication.shared
            guard UIDevice.current.userInterfaceIdiom == .pad, app.supportsMultipleScenes else {
                ctx.infoOnly(); ctx.note("needs an iPad with multiple scenes"); return
            }
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            guard let hosting = Bench.hiddenPages().first?.window?.windowScene else {
                ctx.expect(false, "found the scene hosting the page"); return
            }
            let known = Set(app.connectedScenes.map { ObjectIdentifier($0) })
            var sizes: [String] = []
            func record() {
                let b = hosting.coordinateSpace.bounds
                let s = "\(Int(b.width))x\(Int(b.height))"
                if sizes.last != s { sizes.append(s) }
            }
            record()
            var second: UIWindowScene?
            let outcomes = await bench.burst(ads, count: 20, spacing: 0.5) { i in
                record()
                if i == 2 {
                    let options = UIScene.ActivationRequestOptions()
                    options.requestingScene = hosting
                    app.requestSceneSessionActivation(nil, userActivity: nil, options: options) { ctx.note("activation error: \($0)") }
                }
                if i == 12 {
                    second = app.connectedScenes.compactMap { $0 as? UIWindowScene }.first { !known.contains(ObjectIdentifier($0)) }
                    if let second {
                        app.requestSceneSessionDestruction(second.session, options: nil) { ctx.note("destruction error: \($0)") }
                    }
                }
            }
            await bench.sleep(1.0)
            record()
            ctx.note("hosting window sizes seen: " + sizes.joined(separator: " > "))
            ctx.note(bench.summary(outcomes))
            ctx.expect(second != nil, "a second scene opened beside the page")
            ctx.expect(sizes.count >= 3, "the hosting window shrank and grew back")
            ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed while the window resized")
            ctx.expectFilled(outcomes, "all filled")
            ctx.expect(Bench.hiddenPages().first?.window?.windowScene === hosting, "the page is still hosted in its scene")
            if let second { ctx.expect(!app.connectedScenes.contains(second), "the second scene is gone again") }
        },
        BenchCase(id: "G5a", title: "iPad: second scene opened, scene hosting the page destroyed", kind: .auto) { ctx in
            let bench = ctx.bench
            let app = UIApplication.shared
            guard UIDevice.current.userInterfaceIdiom == .pad, app.supportsMultipleScenes else {
                ctx.infoOnly(); ctx.note("needs an iPad with multiple scenes"); return
            }
            let ads = bench.ensureMain()
            let warm = await bench.fetch(ads)
            ctx.note("page warmed: " + warm.text)
            guard let page = Bench.hiddenPages().first, let hosting = page.window?.windowScene else {
                ctx.expect(false, "found the scene hosting the page"); return
            }
            weak var orphan: WKWebView? = page
            let known = Set(app.connectedScenes.map { ObjectIdentifier($0) })
            let options = UIScene.ActivationRequestOptions()
            options.requestingScene = hosting
            app.requestSceneSessionActivation(nil, userActivity: nil, options: options) { ctx.note("activation error: \($0)") }
            var second: UIWindowScene?
            for _ in 0..<40 {
                await bench.sleep(0.25)
                second = app.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first { !known.contains(ObjectIdentifier($0)) && $0.activationState == .foregroundActive }
                if second != nil { break }
            }
            guard let second else { ctx.expect(false, "a second scene became foreground active"); return }
            ctx.note("second scene at \(Int(second.coordinateSpace.bounds.width))x\(Int(second.coordinateSpace.bounds.height)), "
                     + "hosting scene at \(Int(hosting.coordinateSpace.bounds.width))x\(Int(hosting.coordinateSpace.bounds.height))")
            app.requestSceneSessionDestruction(hosting.session, options: nil) { ctx.note("destruction error: \($0)") }
            for _ in 0..<40 {
                await bench.sleep(0.25)
                if !app.connectedScenes.contains(hosting) { break }
            }
            ctx.expect(!app.connectedScenes.contains(hosting), "the hosting scene disconnected")
            @MainActor func orphanState(_ when: String) {
                guard let orphan else { ctx.note("\(when): the old page's WebView is gone"); return }
                let window = orphan.window
                let scene = window?.windowScene
                ctx.note("\(when): old WebView window \(window == nil ? "nil" : "alive"), its scene "
                         + (scene.map { "\($0 === hosting ? "the dead one" : "another"), state \($0.activationState.rawValue)" } ?? "nil")
                         + ", connected scenes \(app.connectedScenes.count), hidden pages in them \(Bench.hiddenPages().count)")
            }
            orphanState("after the scene went")
            let mark = tap.mark()
            let outcomes = await bench.burst(ads, count: 5, spacing: 0.5)
            ctx.note(bench.summary(outcomes))
            ctx.expect(outcomes.allSatisfy(\.succeeded), "none failed")
            ctx.expectFilled(outcomes, "all filled in the surviving scene")
            ctx.expectLog(tap.since(mark).count(containing: "host window went away,") == 1, "rebuilt once after the window went away")
            ctx.expect(Bench.hiddenPages().first?.window?.windowScene === second, "the page now lives in the surviving scene")
            orphanState("after the burst")
            await bench.sleep(10)
            orphanState("10s later")
            let late = await bench.fetch(ads)
            ctx.note("fetch 10s later: " + late.text)
            orphanState("after that fetch")
            ctx.note("page log since the scene went: " + tap.since(mark).filter { $0.contains("page:") }.map { String($0.suffix(80)) }.joined(separator: " | "))
        },
    ]

    // MARK: H. Banners

    private static func slot(filled: Bool, ratio: CGSize, inspectable: Bool = true, inList: Bool = false) -> BannerSlot {
        let ids = filled ? Bench.filledBanner : Bench.emptyBanner
        return BannerSlot(configuration: .init(accountId: ids.account, siteId: ids.site, channelId: ids.channel,
                                               locationId: ids.location, isInspectable: inspectable),
                          zoneId: ids.zone, ratio: ratio, inList: inList)
    }

    static let bannerCases: [BenchCase] = [
        BenchCase(id: "H1", title: "Filled banner at 8x1, 4x1, 2x1", kind: .auto) { ctx in
            let bench = ctx.bench
            for ratio in [CGSize(width: 8, height: 1), CGSize(width: 4, height: 1), CGSize(width: 2, height: 1)] {
                let result = await bench.showBanner(slot(filled: true, ratio: ratio))
                ctx.note("\(Int(ratio.width))x\(Int(ratio.height)): \(result.event) \(result.ms)ms")
                if ratio.width == 8 { ctx.expect(result.event.hasPrefix("loaded"), "8x1 (the staging creative's ratio) loads") }
                ctx.expect(result.event != "NO CALLBACK", "\(Int(ratio.width))x1 reported an outcome")
                bench.clearBanners()
            }
        },
        BenchCase(id: "H2", title: "No-fill banner collapses fast", kind: .auto) { ctx in
            let bench = ctx.bench
            let result = await bench.showBanner(slot(filled: false, ratio: CGSize(width: 8, height: 1)))
            ctx.note("\(result.event) \(result.ms)ms")
            ctx.expect(result.event == "noFill" && result.ms < 2500, "onNoFill within 2.5s")
        },
        BenchCase(id: "H3", title: "Banner and carousel at the same time", kind: .auto) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            _ = await bench.fetch(ads)
            async let banner = bench.showBanner(slot(filled: true, ratio: CGSize(width: 8, height: 1)))
            let carousel = await bench.burst(ads, count: 5, spacing: 0.05)
            let bannerResult = await banner
            ctx.note("banner \(bannerResult.event) \(bannerResult.ms)ms; carousel " + bench.summary(carousel))
            ctx.expect(bannerResult.event.hasPrefix("loaded"), "banner loaded")
            ctx.expectFilled(carousel, "carousel unaffected")
        },
        BenchCase(id: "H4", title: "Three banners on one screen", kind: .auto) { ctx in
            let bench = ctx.bench
            async let a = bench.showBanner(slot(filled: true, ratio: CGSize(width: 8, height: 1)))
            async let b = bench.showBanner(slot(filled: true, ratio: CGSize(width: 8, height: 1)))
            async let c = bench.showBanner(slot(filled: false, ratio: CGSize(width: 8, height: 1)))
            let results = await [a, b, c]
            ctx.note(results.map { "\($0.event) \($0.ms)ms" }.joined(separator: ", "))
            ctx.expect(results.allSatisfy { $0.event != "NO CALLBACK" }, "all three reported")
            ctx.expect(results[2].event == "noFill", "the no-fill one collapsed")
        },
        BenchCase(id: "H5", title: "Banner in a scrolling list", kind: .hands) { ctx in
            let bench = ctx.bench
            let banner = slot(filled: true, ratio: CGSize(width: 8, height: 1), inList: true)
            let first = await bench.showBanner(banner)
            ctx.note("first load: \(first.event) \(first.ms)ms")
            guard await bench.ask("Scroll the list below all the way down and back up, three times. Check the banner is there each time. Then tap Continue.") else { ctx.note("skipped by tester"); return }
            let events = bench.bannerEvents[banner.id] ?? []
            ctx.note("callbacks over the whole case: \(events)")
            ctx.expect(events.filter { $0.hasPrefix("error") }.isEmpty, "no errors")
            ctx.infoOnly()
        },
        BenchCase(id: "H6", title: "Banner through background and foreground", kind: .hands) { ctx in
            let bench = ctx.bench
            let banner = slot(filled: true, ratio: CGSize(width: 8, height: 1))
            let first = await bench.showBanner(banner)
            ctx.note("first load: \(first.event) \(first.ms)ms")
            guard await bench.ask("Tap Continue, go to the Home Screen for 10 seconds, come back, and look at the banner for 20 seconds.") else { ctx.note("skipped by tester"); return }
            await bench.nextNotification(UIApplication.willEnterForegroundNotification)
            await bench.sleep(20)
            let events = bench.bannerEvents[banner.id] ?? []
            ctx.note("callbacks: \(events)")
            ctx.expect(events.filter { $0.hasPrefix("error") }.isEmpty, "no errors")
            let stillThere = await bench.ask("Is the banner still showing a creative? Continue = yes, Skip = no.")
            ctx.expect(stillThere, "tester confirms the banner is showing")
        },
        BenchCase(id: "H7", title: "Banner while offline", kind: .hands) { ctx in
            let bench = ctx.bench
            guard await bench.ask("Turn ON Airplane Mode (Wi-Fi off too). Come back and tap Continue.") else { ctx.note("skipped by tester"); return }
            let result = await bench.showBanner(slot(filled: true, ratio: CGSize(width: 8, height: 1)))
            ctx.note("\(result.event) \(result.ms)ms")
            ctx.expect(result.event != "NO CALLBACK", "reports an outcome")
            ctx.expect(result.ms < 3000, "does not leave a blank frame for the 8s ceiling")
            _ = await bench.ask("Turn Airplane Mode OFF, then tap Continue.")
        },
    ]

    // MARK: K. Tracker order (the warm-up identity question)

    /// The tracker the app's Home tab creates by hand; the bench creates it itself here, once
    /// per process, so these cases need a fresh launch and K1 must run before K2.
    private static var trackerCreated = false
    private static func createTracker() {
        guard !trackerCreated else { return }
        trackerCreated = true
        _ = SurfsideHelper.createTracker(namespace: "iosTracker", environment: .development,
                                         accountId: "00000-1", sourceId: "00000-2")
    }

    static let orderCases: [BenchCase] = [
        BenchCase(id: "K1", title: "Wrong order: SurfsideAds created before the tracker exists", kind: .auto) { ctx in
            let bench = ctx.bench
            guard !trackerCreated else { ctx.infoOnly(); ctx.note("tracker already exists in this process; run K1 first"); return }
            let mark = tap.mark()
            let ads = SurfsideAds(configuration: bench.config())
            await bench.sleep(2.0)
            let warm = tap.since(mark).filter { $0.contains("page: loading") }
            ctx.note("warm-up: " + warm.map { String($0.suffix(70)) }.joined(separator: " | "))
            ctx.expectLog(warm.count == 1 && warm[0].contains("identity anonymous"), "warm-up loaded anonymous (no tracker yet)")
            createTracker()
            let mark2 = tap.mark()
            let first = await bench.fetch(ads), second = await bench.fetch(ads)
            let lines = tap.since(mark2)
            let reloads = lines.count(containing: "identity changed")
            let users = Set(LogTap.initUsers(lines, account: Bench.account))
            ctx.note("first \(first.text), second \(second.text); reloads \(reloads); web SDK initialised with \(users.sorted())")
            ctx.expect(first.filled && second.filled, "both filled")
            ctx.expectLog(reloads == 1, "exactly one identity reload (the cost of the wrong order)")
            ctx.expectLog(users.count == 1 && users.first != "", "fetches carried the tracker's id")
        },
        BenchCase(id: "K2", title: "Normal order: tracker first, then SurfsideAds; warm-up carries the id, no reload", kind: .auto) { ctx in
            let bench = ctx.bench
            createTracker()
            let mark = tap.mark()
            let ads = SurfsideAds(configuration: bench.config())
            await bench.sleep(2.0)
            let warm = tap.since(mark).filter { $0.contains("page: loading") }
            ctx.note("warm-up: " + warm.map { String($0.suffix(70)) }.joined(separator: " | "))
            ctx.expectLog(warm.count == 1 && warm[0].contains("identity set"), "warm-up loaded with the tracker's id")
            let mark2 = tap.mark()
            let first = await bench.fetch(ads), second = await bench.fetch(ads)
            let lines = tap.since(mark2)
            let users = Set(LogTap.initUsers(lines, account: Bench.account))
            ctx.note("first \(first.text), second \(second.text); web SDK initialised with \(users.sorted())")
            ctx.expect(first.filled && second.filled, "both filled")
            ctx.expect(first.ms < 1000, "first fetch served from the warm page (under 1s)")
            ctx.expectLog(lines.filter { !$0.contains("BENCH") }.count(containing: "page: loading") == 0, "no reload at the first fetch")
            ctx.expectLog(users.count == 1 && users.first != "", "fetches carried the tracker's id")
        },
    ]

    // MARK: I. Build

    static let buildCases: [BenchCase] = [
        BenchCase(id: "I5", title: "Launch timing this launch", kind: .auto) { ctx in
            let bench = ctx.bench
            if let window = bench.firstWindowAt {
                ctx.note("create mode \(bench.createMode): bench visible \(Int(window.timeIntervalSince(Bench.processStart) * 1000))ms after App.init")
            }
            ctx.infoOnly()
        },
    ]

    // MARK: J. Soak

    /// `-benchSoak <minutes>`: one fetch every `-benchSoakEvery` seconds (default 5). Every
    /// fetch, SDK page event and footprint reading goes to the live feed and to
    /// `bench-soak-<runId>.json` (written every minute), so a run that is cut short still
    /// leaves its data. "Stop soak" in the UI ends it early with the checks still run.
    /// With fewer than 50 fetches in 30 minutes (`-benchSoakEvery 60`) the run exercises the
    /// 30 minute recycle rule instead of the count rule (D11).
    static func soak(minutes: Int, every spacing: TimeInterval = 5) -> BenchCase {
        BenchCase(id: "J1", title: "Soak, \(minutes) minutes, one fetch every \(Int(spacing))s", kind: .auto, long: true) { ctx in
            let bench = ctx.bench
            let ads = bench.ensureMain()
            let started = Date()
            let end = started.addingTimeInterval(TimeInterval(minutes * 60))
            let mark = tap.mark()
            var seen = mark
            var outcomes: [Outcome] = []
            var minute = 0
            var lastReading = Date.distantPast
            var lastSave = Date()
            bench.stopRequested = false
            bench.feed = []
            bench.soak = SoakLog(runId: bench.runId, started: started, minutes: minutes)

            @MainActor func reading(_ why: String) {
                guard let mib = Bench.footprintMiB() else { return }
                bench.soak?.readings.append(SoakReading(at: Date(), fetches: outcomes.count, appMiB: mib))
                bench.post(.memory, String(format: "app %.1f MiB (%@)", mib, why))
                lastReading = Date()
            }
            @MainActor func drainPageLog() {
                let fresh = tap.since(seen)
                seen += fresh.count
                for line in fresh {
                    if let range = line.range(of: "SurfsideAdsKit page: ") {
                        let event = String(line[range.upperBound...])
                        bench.soak?.pageEvents.append(ISO8601DateFormatter().string(from: Date()) + " " + event)
                        bench.post(.page, "page: " + event)
                        if event.hasPrefix("ready") { reading("after page load") }
                    } else if line.contains("204 - No bids available") {
                        bench.post(.note, "bidder 204, no bids")
                    }
                }
            }

            reading("start")
            while Date() < end, !bench.stopRequested {
                let latest = await bench.fetch(ads)
                outcomes.append(latest)
                let n = outcomes.count
                let kind: FeedLine.Kind = latest.filled ? .filled : (latest.succeeded ? .empty : .failed)
                let outcome: String
                switch latest.result {
                case .none: outcome = "silent"
                case .success: outcome = latest.filled ? "filled" : "empty"
                case .failure: outcome = "failed"
                }
                let detail: String = { if case .failure(let e)? = latest.result { return "\(e)" } else { return "" } }()
                bench.soak?.samples.append(SoakSample(n: n, at: Date(), ms: latest.ms, outcome: outcome,
                                                      count: latest.products.count, detail: detail))
                bench.post(kind, "#\(n) \(latest.text)")
                drainPageLog()
                if Date().timeIntervalSince(lastReading) >= 60 { reading("every minute") }
                if Date().timeIntervalSince(lastSave) >= 60 { bench.saveSoak(); lastSave = Date() }
                let elapsed = Int(Date().timeIntervalSince(started)) / 60
                if elapsed > minute {
                    minute = elapsed
                    NSLog("%@", "BENCH   soak minute \(minute): " + bench.summary(outcomes))
                }
                await bench.sleep(spacing)
                drainPageLog()
            }
            if bench.stopRequested {
                bench.soak?.stoppedEarly = true
                ctx.note("stopped early by tester after \(Int(Date().timeIntervalSince(started) / 60)) minutes")
            }
            reading("end")
            bench.saveSoak()
            let lines = tap.since(mark)
            ctx.note(bench.summary(outcomes))
            ctx.note("page loads during the soak: \(lines.count(containing: "page: loading")), of which recycles: \(lines.count(containing: "recycle after"))")
            if let readings = bench.soak?.readings, let first = readings.first, let last = readings.last {
                ctx.note(String(format: "app footprint %.1f MiB at start, %.1f MiB at end, peak %.1f MiB",
                                first.appMiB, last.appMiB, readings.map(\.appMiB).max() ?? 0))
            }
            ctx.expect(outcomes.allSatisfy(\.succeeded), "zero failures")
            let empties = outcomes.filter { $0.succeeded && !$0.filled }.count
            ctx.expect(empties * 50 <= outcomes.count, "genuine no-bids under 2% (\(empties) of \(outcomes.count))")
            // The 50-fetch recycle resets the page's load time, so the 30 minute rule can only
            // fire in a run with fewer than 50 fetches per 30 minutes.
            let recycles = lines.filter { $0.contains("recycle after") }
            let fetchesPerHalfHour = Int(1800 / spacing)
            if !bench.stopRequested, fetchesPerHalfHour < 50, minutes >= 31 {
                let byTime = recycles.contains { line in
                    guard let range = line.range(of: "recycle after ") else { return false }
                    return (Int(line[range.upperBound...].prefix { $0.isNumber }) ?? 50) < 50
                }
                ctx.expectLog(byTime, "the 30 minute recycle happened (a recycle logged with under 50 fetches)")
            } else if !bench.stopRequested {
                ctx.expectLog(recycles.count >= outcomes.count / 50, "a recycle per 50 fetches")
            }
        }
    }
}
