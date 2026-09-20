import SwiftUI

private struct EditableFood: Identifiable {
    let id = UUID()
    var item: MealFoodItem
}

/// Everyday correction is separate from nutrient confirmation and Health export.
struct MealEditView: View {
    let meal: MealRecord
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var time: Date
    @State private var foods: [EditableFood]
    @State private var error: String?

    init(meal: MealRecord) {
        self.meal = meal
        _name = State(initialValue: meal.displayTitle == "Meal photo" ? "" : meal.displayTitle)
        _note = State(initialValue: meal.userComment)
        _time = State(initialValue: meal.eatenAt)
        _foods = State(initialValue: meal.foodItems.map { EditableFood(item: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $name, axis: .vertical).lineLimit(1...3).accessibilityIdentifier("meal.edit.name")
                    DatePicker("Eaten at", selection: $time, in: ...Date())
                    TextField("Note · optional", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    ForEach($foods) { $food in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Food", text: $food.item.name, axis: .vertical).lineLimit(1...3).accessibilityLabel("Food name")
                            TextField("Portion · for example, 1 slice", text: $food.item.portion, axis: .vertical).lineLimit(1...3).font(.subheadline).accessibilityLabel("Food portion")
                        }.padding(.vertical, 3)
                    }.onDelete { foods.remove(atOffsets: $0) }
                    Button("Add food", systemImage: "plus") {
                        foods.append(EditableFood(item: MealFoodItem(name: "", portion: "", nutrients: .empty, confidence: 1, evidence: "Entered by you")))
                    }
                } header: { Text("Foods & portions") } footer: {
                    Text("Correct these to match repeated meals. Unknown portions stay separate.")
                }
            }.navigationTitle("Edit meal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("meal.edit.save") }
                }
                .alert("Couldn’t save meal", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }.tint(JournalStyle.accent).interactiveDismissDisabled(changed)
    }

    private var changed: Bool {
        name != (meal.displayTitle == "Meal photo" ? "" : meal.displayTitle) || note != meal.userComment || time != meal.eatenAt || foodsChanged
    }
    private var foodsChanged: Bool {
        let original = meal.foodItems
        return original.count != foods.count || zip(original, foods).contains { $0.name != $1.item.name || $0.portion != $1.item.portion }
    }
    private func save() {
        guard changed else { dismiss(); return }
        do {
            let editedFoods = foodsChanged
            let saved = try MealStore.shared.update(id: meal.id) { record in
                record.userMealName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                record.userComment = note.trimmingCharacters(in: .whitespacesAndNewlines)
                if time != meal.eatenAt {
                    record.eatenAt = time
                    record.timeZoneIdentifier = TimeZone.current.identifier
                }
                record.revision += 1
                // Reject an in-flight analysis based on the earlier note; edits never upload a photo.
                record.analysisRequestID = nil; record.analysisRetryAfter = nil
                if record.status == .analyzing { record.status = record.analysis == nil ? .draft : .estimated }
                if editedFoods {
                    record.userFoodItems = foods.compactMap { food in
                        var item = food.item
                        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !item.name.isEmpty else { return nil }
                        let old = meal.foodItems.first { $0.name == item.name && $0.portion == item.portion }
                        if old == nil {
                            item.confidence = 1; item.evidence = "Entered by you"
                            item.foodEvidence = FoodEvidence(canonicalName: item.name, preparation: nil, brand: nil, ripeness: nil, source: "user_stated")
                            item.nutrients = .empty
                        }
                        return item
                    }
                    record.keepResponseSeparate = false
                }
                if record.status == .confirmed && (editedFoods || time != meal.eatenAt) { record.status = .estimated }
            }
            guard saved != nil else { error = "This meal is no longer in your journal."; return }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
