import SwiftUI

/// Optional review, deliberately separate from the photograph-and-go capture path.
struct JournalNutritionView: View {
  let mealID: UUID
  @Environment(\.dismiss) private var dismiss
  @State private var values = Array(repeating: "", count: 6)
  @State private var message: String?
  @State private var busy = false
  @State private var loaded = false
  private let names = ["Carbohydrate", "Protein", "Fat", "Fibre", "Sugar", "Energy"]
  var body: some View {
    Form {
      if let meal = MealStore.shared.record(id: mealID) {
        Section {
          Text(meal.displayTitle).font(.headline)
          Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(
            .secondary)
        }
        Section {
          ForEach(0..<names.count, id: \.self) { index in
            LabeledContent("\(names[index]) (\(index == 5 ? "kcal" : "g"))") {
              TextField("Unknown", text: $values[index]).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(names[index]).accessibilityIdentifier("nutrition.\(index)")
            }
          }
        } header: {
          Text("Meal totals")
        } footer: {
          Text(
            "Photo estimates can be wrong. Leave unknown quantities blank. Editing nutrition doesn’t change your recorded glucose response."
          )
        }
        if let analysis = meal.analysis, !analysis.assumptions.isEmpty {
          Section {
            DisclosureGroup("Estimation notes") {
              ForEach(analysis.assumptions, id: \.self) {
                Text($0).font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }
        }
        Section {
          if busy { ProgressView("Saving…") }
          Button(
            MealAISettings.writeConfirmedMealsToHealthKit
              ? "Confirm & share with Health" : "Confirm nutrition"
          ) { Task { await confirm() } }
          .disabled(busy || values.allSatisfy { $0.isEmpty }).accessibilityIdentifier(
            "nutrition.confirm")
          if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
        } footer: {
          Text(
            MealAISettings.writeConfirmedMealsToHealthKit
              ? "Only confirmed totals and meal time are shared. Never your photo or note."
              : "Saved on this iPhone. Health sharing is off.")
        }
      } else {
        Label("This meal is no longer available", systemImage: "tray")
      }
    }.navigationTitle("Nutrition review").navigationBarTitleDisplayMode(.inline)
      .disabled(busy).interactiveDismissDisabled(busy)
      .onAppear {
        guard !loaded else { return }
        loaded = true
        if let n = MealStore.shared.record(id: mealID)?.analysis?.nutrients {
          values = [n.carbohydratesG, n.proteinG, n.fatG, n.fiberG, n.sugarG, n.energyKcal].map {
            $0.map { String($0) } ?? ""
          }
        }
      }
  }
  @MainActor private func confirm() async {
    var numbers: [Double?] = []
    for value in values {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if clean.isEmpty {
        numbers.append(nil)
        continue
      }
      guard let number = Double(clean.replacingOccurrences(of: ",", with: ".")), number.isFinite,
        number >= 0, number <= 100_000
      else {
        message = "Use a positive number, zero, or leave the quantity blank."
        return
      }
      numbers.append(number)
    }
    busy = true
    defer { busy = false }
    do {
      guard
        let record = try MealStore.shared.update(
          id: mealID,
          { record in
            let old = record.analysis
            record.analysis = MealAnalysis(
              title: record.displayTitle, summary: old?.summary ?? "Entered by you",
              items: old?.items ?? [],
              nutrients: MealNutrients(
                carbohydratesG: numbers[0], proteinG: numbers[1], fatG: numbers[2],
                fiberG: numbers[3], sugarG: numbers[4], energyKcal: numbers[5]),
              overallConfidence: old?.overallConfidence ?? 1, assumptions: old?.assumptions ?? [],
              questions: old?.questions ?? [], model: old?.model ?? "manual",
              analyzedAt: old?.analyzedAt ?? Date())
            record.status = .confirmed
            record.revision += 1
            record.analysisRequestID = nil
            record.analysisRetryAfter = nil
            record.analysisError = nil
          })
      else {
        message = "This meal is no longer available."
        return
      }
      guard MealAISettings.writeConfirmedMealsToHealthKit else {
        message = "Nutrition confirmed."
        return
      }
      do {
        let id = try await MealHealthKitWriter.shared.replaceHealthKitMeal(for: record)
        _ = try MealStore.shared.update(id: mealID) { current in
          current.healthKitCorrelationUUID = id
          if current.revision != record.revision { current.status = .estimated }
        }
        message = "Confirmed and shared with Apple Health."
      } catch { message = "Saved here. Health export didn’t finish: \(error.localizedDescription)" }
    } catch { message = "Couldn’t save nutrition: \(error.localizedDescription)" }
  }
}
