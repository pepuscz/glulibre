import Foundation
import HealthKit

final class MealHealthKitWriter {
    static let shared = MealHealthKitWriter()

    private let healthStore = HKHealthStore()
    private let mealIDMetadataKey = "LibreDebugMealID"
    private let mealRevisionMetadataKey = "LibreDebugMealRevision"
    private let estimateMetadataKey = "LibreDebugNutritionEstimated"

    private init() {}

    func replaceHealthKitMeal(for record: MealRecord) async throws -> UUID {
        guard HKHealthStore.isHealthDataAvailable() else { throw MealHealthKitError.unavailable }
        guard let analysis = record.analysis, analysis.nutrients.hasAnyValue else {
            throw MealHealthKitError.noNutrition
        }

        let types = try healthTypes()
        try await requestAuthorization(share: types.share, read: types.read)

        if let previousUUID = record.healthKitCorrelationUUID {
            try await deleteCorrelation(uuid: previousUUID, foodType: types.food)
        }

        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: analysis.title,
            mealIDMetadataKey: record.id.uuidString,
            mealRevisionMetadataKey: NSNumber(value: record.revision),
            estimateMetadataKey: NSNumber(value: record.status != .confirmed)
        ]

        var samples = [HKSample]()
        appendSample(value: analysis.nutrients.carbohydratesG, type: types.carbohydrates, unit: .gram(), record: record, metadata: metadata, to: &samples)
        appendSample(value: analysis.nutrients.proteinG, type: types.protein, unit: .gram(), record: record, metadata: metadata, to: &samples)
        appendSample(value: analysis.nutrients.fatG, type: types.fat, unit: .gram(), record: record, metadata: metadata, to: &samples)
        appendSample(value: analysis.nutrients.fiberG, type: types.fiber, unit: .gram(), record: record, metadata: metadata, to: &samples)
        appendSample(value: analysis.nutrients.sugarG, type: types.sugar, unit: .gram(), record: record, metadata: metadata, to: &samples)
        appendSample(value: analysis.nutrients.energyKcal, type: types.energy, unit: .kilocalorie(), record: record, metadata: metadata, to: &samples)

        guard !samples.isEmpty else { throw MealHealthKitError.noNutrition }
        let correlation = HKCorrelation(
            type: types.food,
            start: record.eatenAt,
            end: record.eatenAt,
            objects: Set(samples),
            metadata: metadata
        )
        try await save(correlation)
        NSLog("MEAL_CAPTURE HealthKit saved meal=%@ correlation=%@", record.id.uuidString, correlation.uuid.uuidString)
        return correlation.uuid
    }

    func deleteHealthKitMeal(for record: MealRecord) async throws {
        guard let uuid = record.healthKitCorrelationUUID else { return }
        let types = try healthTypes()
        try await requestAuthorization(share: types.share, read: types.read)
        try await deleteCorrelation(uuid: uuid, foodType: types.food)
    }

    private func appendSample(
        value: Double?,
        type: HKQuantityType,
        unit: HKUnit,
        record: MealRecord,
        metadata: [String: Any],
        to samples: inout [HKSample]
    ) {
        guard let value = value, value.isFinite, value >= 0 else { return }
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        samples.append(HKQuantitySample(type: type, quantity: quantity, start: record.eatenAt, end: record.eatenAt, metadata: metadata))
    }

    private func healthTypes() throws -> MealHealthTypes {
        guard let food = HKObjectType.correlationType(forIdentifier: .food),
              let carbohydrates = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let protein = HKObjectType.quantityType(forIdentifier: .dietaryProtein),
              let fat = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
              let fiber = HKObjectType.quantityType(forIdentifier: .dietaryFiber),
              let sugar = HKObjectType.quantityType(forIdentifier: .dietarySugar),
              let energy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            throw MealHealthKitError.unavailable
        }

        let share: Set<HKSampleType> = [food, carbohydrates, protein, fat, fiber, sugar, energy]
        let read: Set<HKObjectType> = Set(share.map { $0 as HKObjectType })
        return MealHealthTypes(
            food: food,
            carbohydrates: carbohydrates,
            protein: protein,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            energy: energy,
            share: share,
            read: read
        )
    }

    private func requestAuthorization(share: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: share, read: read) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: MealHealthKitError.authorizationDenied)
                }
            }
        }
    }

    private func save(_ object: HKObject) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(object) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: MealHealthKitError.saveFailed)
                }
            }
        }
    }

    private func deleteCorrelation(uuid: UUID, foodType: HKCorrelationType) async throws {
        let correlation: HKCorrelation? = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let query = HKSampleQuery(sampleType: foodType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKCorrelation)
                }
            }
            healthStore.execute(query)
        }

        guard let correlation = correlation else { return }
        let objects: [HKObject] = Array(correlation.objects).map { $0 as HKObject } + [correlation]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.delete(objects) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: MealHealthKitError.deleteFailed)
                }
            }
        }
    }
}

private struct MealHealthTypes {
    let food: HKCorrelationType
    let carbohydrates: HKQuantityType
    let protein: HKQuantityType
    let fat: HKQuantityType
    let fiber: HKQuantityType
    let sugar: HKQuantityType
    let energy: HKQuantityType
    let share: Set<HKSampleType>
    let read: Set<HKObjectType>
}

enum MealHealthKitError: LocalizedError {
    case unavailable
    case authorizationDenied
    case noNutrition
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health nutrition data is unavailable on this device."
        case .authorizationDenied: return "Apple Health permission was not granted. The meal is still saved locally."
        case .noNutrition: return "There are no nutrition values to save to Apple Health."
        case .saveFailed: return "Apple Health could not save this meal."
        case .deleteFailed: return "Apple Health could not replace the previous version of this meal."
        }
    }
}
