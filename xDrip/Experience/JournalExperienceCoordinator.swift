import SwiftUI
import UIKit

/// Adds presentation to the original controller; never owns a Bluetooth or persistence manager.
@MainActor
final class JournalExperienceCoordinator {
  private weak var root: RootViewController?
  private var todayHost: UIHostingController<JournalTodayView>?
  private var journalHost: UIHostingController<JournalListView>?
  private var settingsHost: UIHostingController<JournalSettingsView>?
  private var insightsHost: UIHostingController<JournalInsightsView>?
  private var retainedEngineControllers: [UIViewController] = []
  private var dashboardViews: [UIView] = []
  private let preferences = JournalPreferences()
  private let management = JournalManagement()
  private var captureCoordinator: MealCaptureCoordinator?
  private var didRunSimulatorRoute = false

  init(root: RootViewController) { self.root = root }

  func install() {
    guard todayHost == nil, let root, let tabs = root.tabBarController else { return }
    let model = JournalModel.shared
    MealAnalysisService.shared.start()
    model.sensorProvider = { [weak root] in root?.journalSensorSnapshot() ?? JournalSensorSnapshot()
    }
    preferences.alarmSummaryProvider = { [weak root] in root?.journalAlarmSummaries() ?? [] }
    root.configureJournalManagement(management)
    let today = UIHostingController(
      rootView: JournalTodayView(
        model: model,
        capture: { [weak self] in self?.capture() }, sensor: { [weak self] in self?.showSensor() },
        advanced: { [weak self] in self?.showSettings() },
        insights: { [weak self] in
          guard let self, let insightsHost = self.insightsHost else { return }
          self.root?.tabBarController?.selectedViewController = insightsHost
        }, alerts: { [weak self] in self?.showNotifications() },
        edit: { [weak self] in self?.edit($0) }))
    todayHost = today
    dashboardViews = root.view.subviews
    dashboardViews.forEach { $0.accessibilityElementsHidden = true }
    root.addChild(today)
    today.view.translatesAutoresizingMaskIntoConstraints = false
    root.view.addSubview(today.view)
    root.view.backgroundColor = .systemGroupedBackground
    NSLayoutConstraint.activate([
      today.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
      today.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
      today.view.topAnchor.constraint(equalTo: root.view.topAnchor),
      today.view.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
    ])
    today.didMove(toParent: root)
    root.tabBarItem = UITabBarItem(
      title: "Today", image: UIImage(systemName: "waveform.path.ecg"), tag: 0)
    let journal = UIHostingController(
      rootView: JournalListView(
        model: model,
        capture: { [weak self] in self?.capture() }, edit: { [weak self] in self?.edit($0) }))
    journal.tabBarItem = UITabBarItem(
      title: "Journal", image: UIImage(systemName: "book.closed"), tag: 10)
    journalHost = journal
    // Retain engine owners, not presentation routes. No old screen is reachable.
    retainedEngineControllers = (tabs.viewControllers ?? []).filter { $0 !== root }
    let settings = UIHostingController(
      rootView: JournalSettingsView(model: model, preferences: preferences, management: management))
    settings.tabBarItem = UITabBarItem(
      title: "Settings", image: UIImage(systemName: "gearshape"), tag: 12)
    settingsHost = settings
    let insights = UIHostingController(
      rootView: JournalInsightsView(
        model: model, health: .shared, edit: { [weak self] in self?.edit($0) },
        capture: { [weak self] in self?.capture() }))
    insights.tabBarItem = UITabBarItem(
      title: "Insights", image: UIImage(systemName: "chart.xyaxis.line"), tag: 11)
    insightsHost = insights
    tabs.setViewControllers([root, journal, insights, settings], animated: false)
    tabs.tabBar.tintColor = UIColor(JournalStyle.accent)
    tabs.view.backgroundColor = .systemGroupedBackground
    tabs.tabBar.backgroundColor = nil
    tabs.tabBar.barTintColor = nil
    tabs.tabBar.barStyle = .default
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    tabs.tabBar.standardAppearance = appearance
    tabs.tabBar.scrollEdgeAppearance = appearance

    #if targetEnvironment(simulator) && DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("--journal-rotation-testing") {
        UserDefaults.standard.allowScreenRotation = true
      }
      if arguments.contains("--journal-storage-checks") {
        MealStore.runPersistenceChecks()
        MealHealthKitWriter.runAuthorizationTypeChecks()
        JournalPreferences.runNotificationChecks()
        JournalManagement.runAlarmChecks()
        Task { await MealAnalysisService.runCaptureChecks() }
      }
    #endif
  }

  func didAppear() {
    #if targetEnvironment(simulator) && DEBUG
      guard !didRunSimulatorRoute, JournalModel.shared.isReady else { return }
      didRunSimulatorRoute = true
      let args = ProcessInfo.processInfo.arguments
      if args.contains("--journal-health-demo") {
        JournalHealthContext.shared.useSimulatorPreview()
      }
      if args.contains("--journal-screen"), let journalHost {
        root?.tabBarController?.selectedViewController = journalHost
      }
      if args.contains("--journal-patterns") {
        presenter?.present(
          UIHostingController(rootView: JournalPatternsView(model: .shared)), animated: false)
      }
      if args.contains("--journal-editor") || args.contains("--journal-meal") {
        do {
          let fixture = try MealStore.simulatorMealFixture()
          if args.contains("--journal-editor") {
            edit(fixture.id)
          } else {
            presenter?.present(
              UIHostingController(
                rootView: JournalMealDetail(
                  model: .shared, mealID: fixture.id, edit: { [weak self] in self?.edit($0) })),
              animated: false)
          }
        } catch { assertionFailure(error.localizedDescription) }
      }
      if args.contains("--journal-alerts") { showNotifications() }
      if args.contains("--journal-alarm-response") {
        showAlarmResponse(
          PickerViewData(
            withMainTitle: "Sample glucose alert", withSubTitle: "Snooze for",
            withData: ["15 minutes", "30 minutes", "1 hour"], selectedRow: 0, withPriority: .high,
            actionButtonText: "Snooze", cancelButtonText: "Close", onActionClick: { _ in },
            onCancelClick: {}, didSelectRowHandler: nil))
      }
      if args.contains("--journal-capture") { capture() }
      if args.contains("--journal-quick-preview"),
        let fixture = try? MealStore.simulatorMealFixture()
      {
        let capture = QuickMealCaptureViewController()
        let navigation = UINavigationController(rootViewController: capture)
        capture.showSavedPreview(fixture)
        navigation.view.tintColor = UIColor(JournalStyle.accent)
        presenter?.present(navigation, animated: false)
      }
      if args.contains("--journal-sensor") { showSensor() }
      if args.contains("--journal-settings") { showSettings() }
      if args.contains("--journal-insights"), let insightsHost {
        root?.tabBarController?.selectedViewController = insightsHost
      }
      if args.contains("--food-detail"), let group = JournalModel.shared.foodGroups.first {
        presentSheet(
          FoodResponseDetail(
            model: .shared, health: .shared, groupID: group.id,
            edit: { [weak self] in self?.edit($0) }))
      }
      if args.contains("--food-compare"), JournalModel.shared.foodGroups.count >= 2 {
        let groups = JournalModel.shared.foodGroups
        presentSheet(
          FoodComparisonView(model: .shared, firstID: groups[0].id, secondID: groups[1].id))
      }
      if args.contains("--journal-treatments") {
        presentSheet(JournalSavedRecordsView(management: management))
      }
      if args.contains("--journal-legacy-settings") { showSettings() }
      if args.contains("--journal-legacy-sensor") {
        presentSheet(JournalSensorSetupView(model: .shared, management: management))
      }
      if args.contains("--journal-legacy-alerts") {
        presentSheet(JournalAlarmList(management: management))
      }
      if args.contains("--journal-health") {
        presentSheet(JournalHealthSettingsView(preferences: preferences))
      }
      if args.contains("--journal-ai") {
        presentSheet(JournalAISettingsView(preferences: preferences))
      }
      if args.contains("--journal-workout"),
        let workout = JournalHealthContext.shared.workouts.first
      {
        presentSheet(JournalWorkoutDetail(model: .shared, workout: workout))
      }
    #endif
  }

  private var presenter: UIViewController? {
    var controller = root?.tabBarController?.selectedViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }

  func capture() {
    guard let presenter else { return }
    let capture = QuickMealCaptureViewController()
    let navigation = UINavigationController(rootViewController: capture)
    navigation.view.tintColor = UIColor(JournalStyle.accent)
    navigation.modalPresentationStyle = .pageSheet
    presenter.present(navigation, animated: true)
  }

  private func edit(_ id: UUID) {
    presentSheet(JournalNutritionView(mealID: id))
  }

  private func showSensor() {
    guard JournalModel.shared.isReady else { return }
    presentSheet(JournalSensorView(model: .shared, management: management))
  }

  private func showSettings() {
    guard let settingsHost else { return }
    root?.tabBarController?.selectedViewController = settingsHost
  }

  private func showNotifications() {
    presentSheet(JournalNotificationsView(preferences: preferences, management: management))
  }

  func showSensorSetup() {
    presentSheet(JournalSensorSetupView(model: .shared, management: management))
  }

  func showAlarmResponse(_ data: PickerViewData) {
    presenter?.present(
      UIHostingController(rootView: JournalAlarmResponse(data: data)), animated: true)
  }

  private func presentSheet<Content: View>(_ content: Content) {
    presenter?.present(
      UIHostingController(rootView: JournalNavigationSheet(content: content)), animated: true)
  }

}

struct JournalNavigationSheet<Content: View>: View {
  let content: Content
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      content.toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
      }
    }.tint(JournalStyle.accent)
  }
}
