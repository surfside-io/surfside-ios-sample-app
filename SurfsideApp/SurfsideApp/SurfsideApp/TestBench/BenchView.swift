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
//  Results: Documents/bench-results.json (and bench-results-<runId>.json).
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
            let soak = BenchCases.soak(minutes: minutes)
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
