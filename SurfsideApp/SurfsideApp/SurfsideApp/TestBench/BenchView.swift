//
//  BenchView.swift
//  AdsKit Test Bench tab.
//
//  Launch arguments (all need `-tab 4` to open on this tab):
//    -bench                 start the log tap at launch without running anything
//    -benchAuto             run every automated case unattended
//    -benchOnly A1,D7       restrict any run to these case ids
//    -benchCreate init|appear|lazy   where the long-lived SurfsideAds is created
//    -benchSoak 45          run the soak for that many minutes
//    -benchSoakEvery 60     seconds between soak fetches (default 5; 60 exercises the 30 minute recycle)
//  Results: Documents/bench-results.json (and bench-results-<runId>.json); the soak also
//  writes Documents/bench-soak-<runId>.json every minute.
//

import SwiftUI
import SurfsideAdsKit

@available(iOS 16.0, *)
struct BenchView: View {
    @StateObject private var bench = Bench.shared
    @State private var expanded: Set<String> = []

    private var only: Set<String>? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-benchOnly"), args.indices.contains(i + 1) else { return nil }
        return Set(args[i + 1].split(separator: ",").map(String.init))
    }

    private func cases(_ include: (BenchCase) -> Bool) -> [BenchCase] {
        BenchCases.all.filter { include($0) && (only?.contains($0.id) ?? true) }
    }

    private var automated: [BenchCase] { cases { $0.kind != .hands && !$0.long } }
    private var handsOn: [BenchCase] { cases { $0.kind == .hands && !$0.long } }
    private var longOnes: [BenchCase] { cases { $0.long } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let prompt = bench.prompt { promptCard(prompt) }
                controls
                bannerArea
                ForEach(bench.results) { result in row(result) }
            }
            .padding()
        }
        .navigationTitle("Test Bench")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $bench.showSheet) { Text("Sheet for case G3").padding() }
        .onAppear(perform: appeared)
    }

    private func appeared() {
        guard bench.firstWindowAt == nil else { return }
        bench.firstWindowAt = Date()
        if bench.createMode == "appear" { _ = bench.ensureMain() }
        bench.reset(BenchCases.all)
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-benchSoak"), args.indices.contains(i + 1), let minutes = Int(args[i + 1]) {
            var every: TimeInterval = 5
            if let j = args.firstIndex(of: "-benchSoakEvery"), args.indices.contains(j + 1), let s = Double(args[j + 1]) { every = s }
            let soak = BenchCases.soak(minutes: minutes, every: every)
            bench.reset([soak])
            Task { await bench.run([soak]) }
        } else if args.contains("-benchAuto") {
            Task { await bench.run(automated) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("run \(bench.runId) · create: \(bench.createMode)").font(.caption.monospaced())
            Text(bench.tally.isEmpty ? "not started" : bench.tally).font(.subheadline.bold())
            if !bench.status.isEmpty { Text(bench.status).font(.caption).foregroundColor(.secondary) }
            if let soak = bench.soak {
                SoakPanel(soak: soak, feed: bench.feed, running: bench.running,
                          stop: { bench.stopRequested = true })
            }
        }
    }

    private func promptCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.body.bold())
            HStack {
                Button("Continue") { bench.answer(true) }.buttonStyle(.borderedProminent)
                Button("Skip") { bench.answer(false) }.buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.25))
        .cornerRadius(10)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Automated (\(automated.count))") { Task { await bench.run(automated) } }
                Button("Hands-on (\(handsOn.count))") { Task { await bench.run(handsOn) } }
                Button("Long (\(longOnes.count))") { Task { await bench.run(longOnes) } }
            }
            .buttonStyle(.bordered)
            .disabled(bench.running)
            ShareLink("Share results file", item: Bench.resultsURL).font(.caption)
        }
    }

    @ViewBuilder
    private var bannerArea: some View {
        ForEach(bench.banners.filter { !$0.inList }) { slot in banner(slot) }
        if let listed = bench.banners.first(where: \.inList) {
            ScrollView {
                LazyVStack {
                    banner(listed)
                    ForEach(0..<40, id: \.self) { Text("row \($0)").frame(height: 44) }
                }
            }
            .frame(height: 320)
            .border(Color.secondary.opacity(0.4))
        }
    }

    private func banner(_ slot: BannerSlot) -> some View {
        SurfsideBanner(configuration: slot.configuration,
                       zoneId: slot.zoneId,
                       size: slot.ratio,
                       onLoad: { size in bench.bannerEvent(slot.id, "loaded \(size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "no size")") },
                       onNoFill: { bench.bannerEvent(slot.id, "noFill") },
                       onError: { bench.bannerEvent(slot.id, "error \($0)") })
            .frame(width: 320, height: 320 * slot.ratio.height / slot.ratio.width)
            .frame(maxWidth: .infinity)
    }

    private func row(_ result: CaseResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(icon(result.verdict))
                Text(result.id).font(.caption.monospaced().bold())
                Text(result.title).font(.caption)
                Spacer()
                if !bench.running, let benchCase = BenchCases.all.first(where: { $0.id == result.id }) {
                    Button("run") { Task { await bench.run([benchCase]) } }.font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if expanded.contains(result.id) { expanded.remove(result.id) } else { expanded.insert(result.id) }
            }
            if expanded.contains(result.id) || result.verdict == .fail {
                ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                    Text(note).font(.caption2.monospaced())
                        .foregroundColor(note.hasPrefix("FAIL") ? .red : .secondary)
                }
            }
        }
    }

    private func icon(_ verdict: Verdict) -> String {
        switch verdict {
        case .pass: return "✅"
        case .fail: return "❌"
        case .info: return "ℹ️"
        case .skipped: return "⏭"
        case .running: return "⏳"
        case .pending: return "·"
        }
    }
}

// MARK: - Soak panel

/// Everything the soak produces, as it happens: clock, counts, latency strip, page
/// lifecycle, footprint, and a feed of every fetch.
@available(iOS 16.0, *)
struct SoakPanel: View {
    let soak: SoakLog
    let feed: [FeedLine]
    let running: Bool
    let stop: () -> Void

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private var samples: [SoakSample] { soak.samples }
    private var filled: Int { samples.filter { $0.outcome == "filled" }.count }
    private var empty: Int { samples.filter { $0.outcome == "empty" }.count }
    private var failed: Int { samples.count - filled - empty }
    private var loads: Int { soak.pageEvents.filter { $0.hasPrefix("loading") }.count }
    private var recycles: Int { soak.pageEvents.filter { $0.contains("recycle after") }.count }
    /// Fetches on the current page (the SDK recycles at 50, or 30 minutes).
    private var sincePageLoad: Int {
        guard let lastLoad = feed.first(where: { $0.kind == .page && $0.text.hasPrefix("page: loading") }) else {
            return samples.count
        }
        return samples.filter { $0.at > lastLoad.at }.count
    }
    private var pageLoadedAt: Date {
        feed.first(where: { $0.kind == .page && $0.text.hasPrefix("page: ready") })?.at ?? soak.started
    }

    private func percentile(_ p: Double, of values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The clock ticks on its own so the feed is not rebuilt every second.
            SoakClock(started: soak.started, minutes: soak.minutes, pageLoadedAt: pageLoadedAt,
                      sincePageLoad: sincePageLoad, running: running, stoppedEarly: soak.stoppedEarly, stop: stop)
            stats
            strip
            feedList
        }
    }

    private var stats: some View {
        let all = samples.map(\.ms)
        let recent = samples.suffix(12).map(\.ms)
        let footprint = soak.readings.last?.appMiB
        let first = soak.readings.first?.appMiB
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                         alignment: .leading, spacing: 6) {
            stat("fetches", "\(samples.count)")
            stat("filled", "\(filled)", filled == samples.count ? .green : .primary)
            stat("empty / failed", "\(empty) / \(failed)", failed > 0 ? .red : (empty > 0 ? .orange : .primary))
            stat("median", "\(percentile(0.5, of: all))ms")
            stat("p95 / max", "\(percentile(0.95, of: all)) / \(all.max() ?? 0)ms")
            stat("last 12 median", "\(percentile(0.5, of: recent))ms")
            stat("page loads", "\(loads), recycles \(recycles)")
            stat("app footprint", footprint.map { current in
                let delta = first.map { String(format: " (%+.1f)", current - $0) } ?? ""
                return String(format: "%.1f MiB%@", current, delta)
            } ?? "n/a")
        }
        .padding(8)
        .background(Color.green.opacity(0.12))
        .cornerRadius(8)
    }

    private func stat(_ label: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.footnote.monospacedDigit().bold()).foregroundColor(color)
        }
    }

    /// The last 80 fetches as bars, height by latency, colour by outcome, a rule at 1s.
    private var strip: some View {
        let shown = Array(samples.suffix(80))
        let ceiling = Double(max(1000, shown.map(\.ms).max() ?? 0))
        return VStack(alignment: .leading, spacing: 2) {
            Canvas { context, size in
                let barWidth = size.width / 80
                let ruleY = size.height * (1 - 1000 / ceiling)
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: ruleY)); $0.addLine(to: CGPoint(x: size.width, y: ruleY)) },
                               with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                for (i, sample) in shown.enumerated() {
                    let height = max(2, size.height * Double(sample.ms) / ceiling)
                    let rect = CGRect(x: Double(i) * barWidth + 0.5, y: size.height - height,
                                      width: barWidth - 1, height: height)
                    let color: Color = sample.outcome == "filled" ? .green : (sample.outcome == "empty" ? .orange : .red)
                    context.fill(Path(rect), with: .color(color))
                }
            }
            .frame(height: 56)
            Text("last \(shown.count) fetches, dashed rule at 1s, top \(Int(ceiling))ms")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var feedList: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            Text("feed (newest first)").font(.caption2).foregroundColor(.secondary)
            ForEach(feed.prefix(150)) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text(Self.clock.string(from: line.at)).foregroundColor(.secondary)
                    Text(line.text).foregroundColor(color(line.kind))
                }
                .font(.caption2.monospaced())
            }
        }
    }

    private func color(_ kind: FeedLine.Kind) -> Color {
        switch kind {
        case .filled: return .primary
        case .empty: return .orange
        case .failed: return .red
        case .page: return .blue
        case .memory: return .purple
        case .note: return .secondary
        }
    }
}

/// Elapsed time, progress, and the current page's age against the SDK's recycle rules
/// (50 fetches or 30 minutes since load).
@available(iOS 16.0, *)
struct SoakClock: View {
    let started: Date
    let minutes: Int
    let pageLoadedAt: Date
    let sincePageLoad: Int
    let running: Bool
    let stoppedEarly: Bool
    let stop: () -> Void

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var total: Int { minutes * 60 }
    private var elapsed: Int { min(Int(now.timeIntervalSince(started)), total) }
    private func mmss(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(mmss(elapsed)) of \(minutes):00").font(.title3.monospacedDigit().bold())
                Spacer()
                if running {
                    Button("Stop soak", role: .destructive, action: stop).buttonStyle(.bordered).font(.caption)
                } else {
                    Text(stoppedEarly ? "stopped early" : "finished").font(.caption.bold())
                }
            }
            ProgressView(value: Double(elapsed), total: Double(total))
            Text("this page: \(sincePageLoad) of 50 fetches, \(mmss(Int(now.timeIntervalSince(pageLoadedAt)))) of 30:00")
                .font(.caption2.monospacedDigit()).foregroundColor(.secondary)
        }
        .onReceive(ticker) { now = $0 }
    }
}
