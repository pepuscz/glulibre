import Combine
import CoreData
import UIKit

/// A read-only bridge to the existing app. The original root remains the owner of CGM services.
final class JournalModel: ObservableObject {
    static var isSimulatorUITest: Bool {
        #if targetEnvironment(simulator) && DEBUG
        return ProcessInfo.processInfo.arguments.contains("--journal-ui-testing")
        #else
        return false
        #endif
    }
    static let shared = JournalModel()
    @Published private(set) var points: [JournalGlucosePoint] = []
    @Published private(set) var meals: [MealRecord] = []
    @Published private(set) var foodGroups: [FoodResponseGroup] = []
    private var foodPoints: [JournalGlucosePoint] = []
    @Published private(set) var now = Date()
    @Published private(set) var isMgDl = true
    @Published private(set) var low = 70.0
    @Published private(set) var high = 180.0
    @Published private(set) var storageIssue: String?
    @Published private(set) var isReady = false
    @Published private(set) var sensor = JournalSensorSnapshot()
    var sensorProvider: (() -> JournalSensorSnapshot)?
    private var accessor: BgReadingsAccessor?
    private weak var observedContext: NSManagedObjectContext?
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: .mealStoreDidChange)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reloadMeals() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, UIApplication.shared.applicationState == .active,
                      let context = notification.object as? NSManagedObjectContext,
                      context === self.observedContext || context === self.observedContext?.parent else { return }
                self.refresh()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshUnits() }.store(in: &subscriptions)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard UIApplication.shared.applicationState == .active else { return }
                self?.now = Date()
                self?.refreshSensor()
            }.store(in: &subscriptions)
        reloadMeals()
        refreshSensor()
        refreshUnits()
    }

    func bind(to accessor: BgReadingsAccessor, context: NSManagedObjectContext) {
        self.accessor = accessor
        observedContext = context
        isReady = true
        refresh()
    }

    func refresh() {
        now = Date()
        if let accessor {
            let snapshots = accessor.getLatestBgReadingSnapshots(limit: nil, fromDate: now.addingTimeInterval(-90 * 86400 - 900), forSensor: nil, ignoreRawData: true, ignoreCalculatedValue: false)
            foodPoints = GlucoseObservations.valid(snapshots.map {
                JournalGlucosePoint(date: $0.timeStamp, mgDl: $0.calculatedValue, sensorID: $0.sensorID)
            }, now: now)
            points = foodPoints.filter { $0.date >= now.addingTimeInterval(-14 * 86400) }
        }
        refreshUnits()
        reloadMeals()
        refreshSensor()
        #if targetEnvironment(simulator) && DEBUG
        if ProcessInfo.processInfo.arguments.contains("--journal-demo") {
            points = (0...288).map { index in
                let minute = Double(index * 5)
                let value = 96 + 9 * sin(minute / 100) + 45 * exp(-pow((minute - 1330) / 40, 2))
                return JournalGlucosePoint(date: now.addingTimeInterval(-86400 + minute * 60), mgDl: value, sensorID: "simulated")
            }.filter { $0.date < now.addingTimeInterval(-5 * 3600) || $0.date > now.addingTimeInterval(-4.5 * 3600) }
            foodPoints = points
            rebuildFoodGroups()
        }
        if ProcessInfo.processInfo.arguments.contains("--food-preview") { useFoodPreview() }
        if ProcessInfo.processInfo.arguments.contains("--journal-empty") {
            points = []; foodPoints = []; meals = []; foodGroups = []
        }
        #endif
    }

    private func reloadMeals() {
        #if targetEnvironment(simulator) && DEBUG
        if isReady && ProcessInfo.processInfo.arguments.contains("--food-preview") { useFoodPreview(); return }
        #endif
        meals = MealStore.shared.all()
        storageIssue = MealStore.shared.loadError
        rebuildFoodGroups()
    }

    private func rebuildFoodGroups() {
        foodGroups = FoodResponseCore.groups(meals: meals.map(\.responseInput), points: foodPoints, now: now)
    }

    #if targetEnvironment(simulator) && DEBUG
    private func useFoodPreview() {
        let fixture = MealRecord(id: UUID(), capturedAt: now, eatenAt: now, timeZoneIdentifier: "Europe/Prague",
            imageFilename: "synthetic-preview-no-photo.jpg", imageSHA256: "preview", userComment: "SIMULATOR PREVIEW ONLY",
            status: .estimated, analysis: MealAnalysis(title: "Sample", summary: "Synthetic preview", items: [], nutrients: .empty,
                overallConfidence: 0.9, assumptions: [], questions: [], model: "simulator", analyzedAt: now),
            analysisError: nil, healthKitCorrelationUUID: nil, revision: 1, createdAt: now, updatedAt: now)
        var examples: [MealRecord] = []
        var samples: [JournalGlucosePoint] = []
        for day in 0..<3 {
            for variation in 0..<2 {
                var meal = fixture
                meal.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", day * 2 + variation + 1))!
                meal.eatenAt = now.addingTimeInterval(-Double(day * 86400 + (variation == 0 ? 3 : 9) * 3600))
                meal.analysis?.title = variation == 0 ? "Banana" : "Banana & plain yogurt"
                meal.analysis?.items = [MealFoodItem(name: "Banana", portion: "1 medium", nutrients: .empty, confidence: 0.9, evidence: "Synthetic preview")]
                if variation == 1 { meal.analysis?.items.append(MealFoodItem(name: "Plain yogurt", portion: "150 g", nutrients: .empty, confidence: 0.9, evidence: "Synthetic preview")) }
                examples.append(meal)
                samples += stride(from: -15, through: 125, by: 5).map { minute in
                    let delta = minute < 0 ? 0 : max(0, 1 - abs(Double(minute) - 45) / 55) * Double((variation == 0 ? 48 : 26) + day * 4)
                    return JournalGlucosePoint(date: meal.eatenAt.addingTimeInterval(Double(minute * 60)), mgDl: 95 + delta, sensorID: "synthetic-food-preview")
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--food-occasions"), let first = examples.first {
            var course = first
            course.id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
            course.eatenAt = first.eatenAt.addingTimeInterval(600)
            course.analysis?.title = "Toast course"
            course.analysis?.items = [MealFoodItem(name: "Toast", portion: "1 slice", nutrients: .empty, confidence: 0.9, evidence: "Synthetic preview")]
            var snack = course
            snack.id = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
            snack.eatenAt = first.eatenAt.addingTimeInterval(3600)
            snack.analysis?.title = "Later snack"
            examples += [course, snack]
        }
        meals = examples
        foodPoints = samples.sorted { $0.date < $1.date }
        points = foodPoints
        rebuildFoodGroups()
    }
    #endif

    func refreshSensor() { sensor = sensorProvider?() ?? JournalSensorSnapshot() }

    private func refreshUnits() {
        isMgDl = UserDefaults.standard.bloodGlucoseUnitIsMgDl
        low = UserDefaults.standard.lowMarkValue
        high = UserDefaults.standard.highMarkValue
    }

    var unit: String { isMgDl ? "mg/dL" : "mmol/L" }
    func value(_ mgDl: Double) -> Double { isMgDl ? mgDl : mgDl / 18.0182 }
    func formatted(_ mgDl: Double) -> String { value(mgDl).formatted(.number.precision(.fractionLength(isMgDl ? 0 : 1))) }
    var latest: JournalGlucosePoint? { points.last }
    var isStale: Bool { latest.map { now.timeIntervalSince($0.date) > GlucoseObservations.maximumGap } ?? true }
    var freshness: String {
        guard let latest else { return "Waiting for the first reading" }
        let minutes = max(0, Int(now.timeIntervalSince(latest.date) / 60))
        return minutes == 0 ? "Updated just now" : "Last reading \(minutes) min ago"
    }
    func observation(for meal: MealRecord) -> GlucoseObservations.MealObservation {
        let occasion = occasion(for: meal)
        let others = FoodResponseCore.occasions(meals: meals.map(\.responseInput), now: now)
            .filter { $0.id != occasion.id }.map(\.date)
        return GlucoseObservations.meal(at: occasion.date, otherMealDates: others, points: mealPoints(for: meal), now: now)
    }
    func occasion(for meal: MealRecord) -> MealOccasion {
        FoodResponseCore.occasions(meals: meals.map(\.responseInput), now: now)
            .first { $0.meals.contains { $0.id == meal.id } } ?? MealOccasion(meals: [meal.responseInput])
    }
    func mealPoints(for meal: MealRecord) -> [JournalGlucosePoint] {
        let start = occasion(for: meal).date
        return FoodResponseCore.slice(foodPoints, from: start.addingTimeInterval(-900), through: start.addingTimeInterval(7200))
    }
}
