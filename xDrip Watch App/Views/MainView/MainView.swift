import Charts
import SwiftUI

/// Wrist-sized observation, not a second configuration surface or sensor controller.
struct MainView: View {
  @EnvironmentObject private var state: WatchStateModel
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .largeTitle) private var readingScale: CGFloat = 1
  var now: Date
  private var compact: Bool { WKInterfaceDevice.current().screenBounds.width < 185 }

  private var fresh: Bool {
    WatchGlancePolicy.isFresh(value: state.bgValueInMgDl(), date: state.bgReadingDate(), now: now)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if !fresh {
        Text(state.bgReadingDate() == nil ? "Waiting for iPhone" : "Reading out of date")
          .font(.headline).foregroundStyle(.orange)
      }
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(fresh ? WatchGlancePolicy.valueText(state.bgValueInMgDl(), isMgDl: state.isMgDl) : "—")
          .font(
            .system(size: (compact ? 38 : 44) * readingScale, weight: .semibold, design: .rounded)
          )
          .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
          .accessibilityIdentifier("watch.glucose")
        if fresh {
          Text(WatchGlancePolicy.trendSymbol(state.slopeOrdinal))
            .font(.title2).foregroundStyle(.mint)
            .accessibilityLabel(WatchGlancePolicy.trendDescription(state.slopeOrdinal))
        }
        Spacer(minLength: 2)
        if !typeSize.isAccessibilitySize { unitLabel }
      }.privacySensitive()
      if typeSize.isAccessibilitySize { unitLabel }
      if !fresh, let date = state.bgReadingDate() {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            "Last \(WatchGlancePolicy.valueText(state.bgValueInMgDl(), isMgDl: state.isMgDl)) \(state.bgUnitString())"
          )
          Text(WatchGlancePolicy.ageText(date: date, now: now))
        }.font(.caption2).foregroundStyle(.secondary).privacySensitive()
      }
      if state.bgReadingDates.isEmpty {
        Image(systemName: "iphone.radiowaves.left.and.right")
          .font(.largeTitle).foregroundStyle(.mint).frame(maxWidth: .infinity).padding(
            .vertical, 12)
        Text("Open \(ConstantsHomeView.applicationName) on iPhone.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        WatchHistoryChart(
          values: state.bgReadingValues, dates: state.bgReadingDates,
          sensorIDs: state.bgReadingSensorIDs, isMgDl: state.isMgDl, now: now, fresh: fresh
        )
        .frame(height: compact ? 72 : 104).privacySensitive()
        .accessibilityIdentifier("watch.chart")
        HStack {
          Text("3 hours")
          Spacer()
          Text("Now").accessibilityIdentifier("watch.chart.end")
        }
        .font(.caption2).foregroundStyle(.secondary)
        if !fresh {
          Text("Open \(ConstantsHomeView.applicationName) on iPhone.")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
    }.padding(.horizontal, 6)
  }

  private var unitLabel: some View {
    Text(state.bgUnitString()).font(.caption2).foregroundStyle(.secondary)
      .lineLimit(1).fixedSize()
  }
}

struct WatchMealView: View {
  @EnvironmentObject private var state: WatchStateModel
  var now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Last meal", systemImage: "fork.knife").font(.caption).foregroundStyle(.mint)
      if let meal = state.lastMeal, now.timeIntervalSince1970 - meal.eatenAt < 86400,
        meal.eatenAt <= now.timeIntervalSince1970
      {
        Text(meal.title).font(.headline).fixedSize(horizontal: false, vertical: true)
        if meal.state == "ready", let rise = meal.riseMgDl, rise.isFinite {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(
              "\(rise >= 0 ? "+" : "−")\(WatchGlancePolicy.valueTextForRise(abs(rise), isMgDl: state.isMgDl))"
            )
            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(state.bgUnitString()).font(.caption2).foregroundStyle(.secondary)
          }
          Text("Peak rise · 2 hours").font(.caption).foregroundStyle(.secondary)
        } else if meal.state == "collecting" {
          let elapsed = max(0, now.timeIntervalSince1970 - meal.eatenAt)
          if elapsed < 7200 {
            ProgressView(value: elapsed, total: 7200).tint(.mint)
            Text("\(Int(ceil((7200 - elapsed) / 60))) min to observe")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("Response pending")
              .font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Label("Response unavailable", systemImage: "chart.xyaxis.line").font(.caption)
          Text(meal.detail).font(.caption2).foregroundStyle(.secondary)
        }
        Text(
          "Meal at \(Date(timeIntervalSince1970: meal.eatenAt).formatted(date: .omitted, time: .shortened))"
        )
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityIdentifier("watch.meal.date")
      } else {
        Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(.mint)
          .frame(maxWidth: .infinity).padding(.vertical, 10)
        Text("Capture food on iPhone").font(.headline)
        Text("Your latest meal and its response appear here.").font(.caption).foregroundStyle(
          .secondary)
      }
    }.padding(.horizontal, 6).privacySensitive()
  }
}

private struct WatchHistoryChart: View {
  let values: [Double]
  let dates: [Date]
  let sensorIDs: [String]
  let isMgDl: Bool
  let now: Date
  let fresh: Bool
  private struct Point: Identifiable {
    let date: Date
    let value: Double
    let segment: Int
    var id: Date { date }
  }
  private var points: [Point] {
    let samples = Array(zip(dates, values)).enumerated().map { index, sample in
      (sample.0, sample.1, sensorIDs.indices.contains(index) ? sensorIDs[index] : "")
    }.filter {
      $0.0 >= now.addingTimeInterval(-10800) && $0.0 <= now && $0.1.isFinite && $0.1 > 12
    }.sorted { $0.0 < $1.0 }
    var segment = 0
    var previous: Date?
    var previousSensor: String?
    return samples.compactMap { date, value, sensor in
      if previous == date { return nil }
      if let previous, date.timeIntervalSince(previous) > 600 || previousSensor != sensor {
        segment += 1
      }
      previous = date
      previousSensor = sensor
      return Point(date: date, value: isMgDl ? value : value / 18.0182, segment: segment)
    }
  }
  var body: some View {
    Chart(points) { point in
      LineMark(
        x: .value("Time", point.date), y: .value("Glucose", point.value),
        series: .value("Segment", point.segment)
      )
      .interpolationMethod(.linear).lineStyle(StrokeStyle(lineWidth: 2))
      .foregroundStyle(fresh ? Color.mint : Color.gray)
    }
    .chartXScale(domain: now.addingTimeInterval(-10800)...now)
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis(.hidden)
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 2)) { _ in
        AxisValueLabel()
        AxisGridLine()
      }
    }
    .accessibilityLabel("Glucose history for the last three hours. Gaps indicate missing readings.")
  }
}
