import SwiftUI

struct RootView: View {
  @EnvironmentObject private var watchState: WatchStateModel
  @Environment(\.scenePhase) private var phase
  @Environment(\.isLuminanceReduced) private var dimmed
  @Environment(\.dynamicTypeSize) private var typeSize
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
        // One native scroll owner for both touch and Digital Crown.
        // Nested scrolling inside vertical pages can trap navigation at a boundary.
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              MainView(now: now).id("watch.now")
              Divider().padding(.horizontal, 6)
              WatchMealView(now: now).id("watch.meal")
            }.padding(.bottom, 12)
          }.accessibilityIdentifier("watch.content")
            .onAppear {
              #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--watch-meal") {
                  DispatchQueue.main.async { proxy.scrollTo("watch.meal", anchor: .top) }
                }
              #endif
            }
        }
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
      if value == .active {
        now = Date()
        watchState.requestWatchStateUpdate()
      }
    }
    .onChange(of: dimmed) { _, value in
      if !value {
        now = Date()
        watchState.requestWatchStateUpdate()
      }
    }
    .onAppear {
      now = Date()
      watchState.requestWatchStateUpdate()
    }
  }
}
