// swift-tools-version: 5.9
import PackageDescription

// Pure observation logic can be tested without an iPhone, sensor, credentials, or UIKit.
let package = Package(
    name: "GlucoseObservationCore",
    products: [.library(name: "GlucoseObservationCore", targets: ["GlucoseObservationCore"])],
    targets: [
        .target(name: "WatchCompanionCore", path: "xDrip/Managers/Watch", exclude: ["WatchManager.swift"], sources: ["WatchState.swift"]),
        .testTarget(name: "WatchCompanionCoreTests", dependencies: ["WatchCompanionCore"], path: "Tests/WatchCore"),
        .target(name: "GlucoseObservationCore", path: "xDrip/Experience",
                exclude: ["JournalModel.swift", "JournalViews.swift", "JournalExperienceCoordinator.swift", "JournalPreferences.swift", "JournalSettingsViews.swift", "JournalHealthContext.swift", "JournalInsightsView.swift", "FoodLibraryViews.swift", "MealEditView.swift", "JournalManagement.swift", "JournalManagementViews.swift", "JournalNutritionView.swift", "JournalServiceView.swift"],
                sources: ["GlucoseObservations.swift", "ReadingNotificationPolicy.swift", "GlucoseReference.swift", "FoodResponseCore.swift", "MealPhotoTime.swift"]),
        .testTarget(name: "GlucoseObservationCoreTests", dependencies: ["GlucoseObservationCore"], path: "Tests/ObservationCore")
    ]
)
