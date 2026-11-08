// swift-tools-version: 5.9
import PackageDescription

// Pure observation logic can be tested without an iPhone, sensor, credentials, or UIKit.
let package = Package(
    name: "GlucoseObservationCore",
    platforms: [.macOS(.v12)],
    products: [.library(name: "GlucoseObservationCore", targets: ["GlucoseObservationCore"])],
    targets: [
        .target(name: "AlertPresentationCore", path: "xDrip/Managers/Alerts",
                exclude: ["AlertKind.swift", "AlertManager.swift", "AlertSnoozeStatus.swift", "AlertUrgencyType.swift", "SnoozeParameters.swift"], sources: ["AlertNotificationDictionary.swift"]),
        .testTarget(name: "AlertPresentationCoreTests", dependencies: ["AlertPresentationCore"], path: "Tests/AlertPresentationCore"),
        .target(name: "SmartGuideCore", path: "xDrip/BluetoothTransmitter/CGM/SmartGuide",
                exclude: ["CGMSmartGuideTransmitter.swift", "SmartGuidePeripheral.swift"], sources: ["SmartGuideProtocol.swift", "SmartGuideCalibration.swift"]),
        .testTarget(name: "SmartGuideCoreTests", dependencies: ["SmartGuideCore"], path: "Tests/SmartGuideCore"),
        .target(name: "WatchCompanionCore", path: "xDrip/Managers/Watch", exclude: ["WatchManager.swift"], sources: ["WatchState.swift"]),
        .testTarget(name: "WatchCompanionCoreTests", dependencies: ["WatchCompanionCore"], path: "Tests/WatchCore"),
        .target(name: "GlucoseObservationCore", path: "xDrip/Experience",
                exclude: ["JournalModel.swift", "JournalViews.swift", "JournalExperienceCoordinator.swift", "JournalPreferences.swift", "JournalSettingsViews.swift", "JournalHealthContext.swift", "JournalInsightsView.swift", "FoodLibraryViews.swift", "MealEditView.swift", "JournalManagement.swift", "JournalManagementViews.swift", "JournalNutritionView.swift", "JournalServiceView.swift", "JournalBackupService.swift", "JournalBackupView.swift", "JournalMovementViews.swift"],
                sources: ["GlucoseObservations.swift", "ReadingNotificationPolicy.swift", "GlucoseReference.swift", "FoodResponseCore.swift", "MealPhotoTime.swift", "JournalBackupArchive.swift", "MealMovement.swift"]),
        .testTarget(name: "GlucoseObservationCoreTests", dependencies: ["GlucoseObservationCore"], path: "Tests/ObservationCore")
    ]
)
