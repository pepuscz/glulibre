import SwiftUI
import Charts

struct JournalEarlierReadingsView: View {
    @ObservedObject var management: JournalManagement
    let serial: String
    @State private var reference: GlucoseAdjustment?
    @State private var samples: [GlucoseAdjustment.Sample] = []
    @State private var adjusted = true
    @State private var error: String?
    @State private var addingMeter = false
    private var usesMgDl: Bool { UserDefaults.standard.bloodGlucoseUnitIsMgDl }
    private var unit: String { usesMgDl ? "mg/dL" : "mmol/L" }
    private func value(_ mg: Double) -> Double { usesMgDl ? mg : mg / 18.0182 }
    private func format(_ mg: Double) -> String { String(format: usesMgDl ? "%.0f" : "%.1f", value(mg)) }
    private var points: [JournalGlucosePoint] {
        samples.compactMap { sample in
            guard let reference, sample.sensorID == reference.sensorID, sample.date <= reference.measuredAt,
                  sample.trendOnly else { return nil }
            guard let amount = adjusted ? reference.adjusted(sample) : sample.value else { return nil }
            return .init(date: sample.date, mgDl: amount, sensorID: sample.sensorID)
        }
    }
    private var domain: ClosedRange<Double> {
        let amounts = samples.filter { $0.sensorID == reference?.sensorID && $0.trendOnly && $0.date <= (reference?.measuredAt ?? .distantPast) }
            .flatMap { [$0.value, reference?.adjusted($0)].compactMap { $0 } }.map(value)
        let pad = value(10)
        return ((amounts.min() ?? value(70)) - pad)...((amounts.max() ?? value(140)) + pad)
    }
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.secondary) }
            else if let reference {
                Section {
                    Picker("Readings", selection: $adjusted) {
                        Text("Original").tag(false)
                        Text("Adjusted").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("history.series")
                    Text(adjusted ? "Estimated adjustment" : "Recorded readings")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("history.label")
                    Chart {
                        ForEach(Array(GlucoseObservations.segments(points).enumerated()), id: \.offset) { index, segment in
                            ForEach(segment) { point in
                                LineMark(x: .value("Time", point.date), y: .value(unit, value(point.mgDl)), series: .value("Segment", index))
                                    .foregroundStyle(JournalStyle.accent)
                            }
                        }
                    }.chartYScale(domain: domain)
                        .chartXScale(range: .plotDimension(padding: 12))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.hour())
                            }
                        }
                        .frame(height: 240)
                        .accessibilityLabel(adjusted ? "Estimated earlier glucose" : "Original earlier glucose")
                    LabeledContent("Adjustment", value: "\(reference.offset >= 0 ? "+" : "")\(format(reference.offset)) \(unit)")
                    LabeledContent("Meter reading", value: "\(format(reference.meterMgDl)) \(unit)")
                    LabeledContent("Sensor estimate", value: "\(format(reference.baselineMgDl)) \(unit)")
                    LabeledContent("Measured", value: reference.measuredAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section {
                    DisclosureGroup("About this estimate") {
                        Text(reference.origin == .historicalMeter
                            ? "Matches the meter’s measurement time between nearby stable sensor readings. Their difference is applied to earlier uncalibrated readings from this sensor."
                            : "Uses the difference between one meter reading and nearby stable sensor readings. The same offset is applied to earlier uncalibrated readings from this sensor.")
                        Text("This estimate does not calibrate the sensor.")
                        Text("Accuracy further back is unknown. A fixed offset moves the curve without changing meal-to-baseline rises. Out-of-range estimates are omitted.")
                        Text("Originals, alerts and Health data stay unchanged.")
                    }.foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("No adjustment yet").font(.headline)
                    Text("Add a meter reading and its measurement time.").foregroundStyle(.secondary)
                    Button("Add meter reading") { addingMeter = true }
                }
            }
        }.navigationTitle("Earlier readings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add meter reading", systemImage: "plus") { addingMeter = true }
                        .accessibilityIdentifier("history.addMeter")
                }
            }
            .onAppear(perform: reload)
            .sheet(isPresented: $addingMeter, onDismiss: reload) { HistoricalMeterView(management: management, serial: serial) }
    }
    private func reload() {
        do {
            reference = try GlucoseAdjustmentStore.shared.all().filter { $0.serial == serial && $0.available }.max { $0.measuredAt < $1.measuredAt }
            samples = try management.earlierReadings(serial: serial)
            error = nil
        } catch { self.error = "Couldn’t load earlier readings. Try again." }
        #if DEBUG && targetEnvironment(simulator)
        if JournalModel.isSimulatorUITest && ProcessInfo.processInfo.arguments.contains("--history-adjustment-preview") {
            let now = Date()
            samples = (0...144).map { i in
                let minutes = Double(i * 5)
                return .init(date: now.addingTimeInterval(-minutes * 60), value: minutes < 20 ? 100 : 100 + 30 * exp(-pow((minutes - 180) / 40, 2)), sensorID: "synthetic", trendOnly: true)
            }.sorted { $0.date < $1.date }
            reference = try? GlucoseAdjustment.historical(serial: serial, minute: 720, meter: 110, at: now.addingTimeInterval(-120), samples: samples)
            error = nil
        }
        #endif
    }
}


private struct HistoricalMeterView: View {
    @ObservedObject var management: JournalManagement
    let serial: String
    @Environment(\.dismiss) private var dismiss
    @State private var enteredValue = ""
    @State private var measuredAt = Date()
    @State private var usesMgDl = UserDefaults.standard.bloodGlucoseUnitIsMgDl
    @State private var error: String?
    private var amount: Double? { Double(enteredValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meter value", text: $enteredValue)
                        .keyboardType(.decimalPad).accessibilityIdentifier("history.meterValue")
                    Picker("Unit", selection: $usesMgDl) {
                        Text("mmol/L").tag(false)
                        Text("mg/dL").tag(true)
                    }.pickerStyle(.segmented)
                    DatePicker("Measured", selection: $measuredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("Estimates earlier readings. Does not calibrate the sensor.")
                }
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Meter reading").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount == nil)
                }
            }
        }
    }
    private func save() {
        guard let amount else { return }
        // The picker exposes minutes: retain that precision, not hidden current seconds.
        let date = Calendar.current.dateInterval(of: .minute, for: measuredAt)?.start ?? measuredAt
        do {
            try management.saveHistoricalMeter(serial: serial, value: amount, usesMgDl: usesMgDl, measuredAt: date)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
