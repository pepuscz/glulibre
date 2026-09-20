import SwiftUI

struct RootView: View {
    @EnvironmentObject private var watchState: WatchStateModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page = 0
    @State private var now = Date()

    private var previewLarge: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--watch-large")
        #else
        return false
        #endif
    }
    private var previewDimmed: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--watch-dimmed")
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if dimmed || previewDimmed {
                VStack(spacing: 8) {
                    Image(systemName: "drop.fill").font(.title2).foregroundStyle(.mint)
                    Text("Raise wrist to view").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $page) {
                    MainView(now: now).tag(0)
                    WatchMealView(now: now).tag(1)
                    WatchConnectionView(now: now).tag(2)
                }.tabViewStyle(.verticalPage)
            }
        }
        .containerBackground(.black, for: .navigation)
        .navigationTitle("")
        .environment(\.dynamicTypeSize, previewLarge ? .accessibility3 : typeSize)
        .onReceive(watchState.timer) { date in
            now = date
            if phase == .active && !dimmed { watchState.requestWatchStateUpdate() }
        }
        .onChange(of: phase) { _, value in
            if value == .active { now = Date(); watchState.requestWatchStateUpdate() }
        }
        .onChange(of: dimmed) { _, value in
            if !value { now = Date(); watchState.requestWatchStateUpdate() }
        }
        .onAppear {
            now = Date()
            watchState.requestWatchStateUpdate()
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--watch-meal") { page = 1 }
            if ProcessInfo.processInfo.arguments.contains("--watch-connection") { page = 2 }
            #endif
        }
    }
}
