import UIKit

private enum MealAnalysisSetting: Int, CaseIterable {
    case apiKey
    case model
    case healthKit
}

final class SettingsViewMealAnalysisSettingsViewModel: SettingsViewModelProtocol {
    private weak var viewController: UIViewController?
    private var rowReloadClosure: ((Int) -> Void)?

    func sectionTitle() -> String? { "🍽 Meal Photos & AI" }

    func sectionFooter() -> String? {
        "When automatic meal analysis is on in Settings → Meal analysis, new photos and notes are sent to OpenAI using your saved key. Old meals are not uploaded automatically. The key stays in Keychain. Health export requires review."
    }

    func numberOfRows() -> Int { MealAnalysisSetting.allCases.count }

    func settingsRowText(index: Int) -> String {
        switch MealAnalysisSetting(rawValue: index)! {
        case .apiKey: return "OpenAI API key"
        case .model: return "OpenAI model"
        case .healthKit: return "Confirmed meals to Apple Health"
        }
    }

    func detailedText(index: Int) -> String? {
        switch MealAnalysisSetting(rawValue: index)! {
        case .apiKey: return MealAISettings.hasAPIKey ? "Configured" : "Not configured"
        case .model: return MealAISettings.model
        case .healthKit: return nil
        }
    }

    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        switch MealAnalysisSetting(rawValue: index)! {
        case .apiKey, .model: return .disclosureIndicator
        case .healthKit: return .none
        }
    }

    func uiView(index: Int) -> UIView? {
        guard MealAnalysisSetting(rawValue: index) == .healthKit else { return nil }
        return UISwitch(isOn: MealAISettings.writeConfirmedMealsToHealthKit) { isOn in
            MealAISettings.writeConfirmedMealsToHealthKit = isOn
        }
    }

    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        switch MealAnalysisSetting(rawValue: index)! {
        case .apiKey:
            return .callFunction { [weak self] in self?.presentAPIKeyEditor() }
        case .model:
            return .callFunction { [weak self] in self?.presentModelEditor() }
        case .healthKit:
            return .nothing
        }
    }

    func isEnabled(index: Int) -> Bool { true }
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool { false }
    func storeMessageHandler(messageHandler: @escaping ((String, String) -> Void)) {}

    func storeUIViewController(uIViewController: UIViewController) {
        viewController = uIViewController
    }

    func storeRowReloadClosure(rowReloadClosure: @escaping ((Int) -> Void)) {
        self.rowReloadClosure = rowReloadClosure
    }

    private func presentAPIKeyEditor() {
        guard let viewController = viewController else { return }
        let alert = UIAlertController(
            title: "OpenAI API Key",
            message: "The key is stored only in this iPhone’s Keychain. Leave the field empty and tap Cancel to keep the current key.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = MealAISettings.hasAPIKey ? "A key is already configured" : "sk-..."
            field.isSecureTextEntry = true
            field.textContentType = .password
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if MealAISettings.hasAPIKey {
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                do {
                    try MealAISettings.removeAPIKey()
                    self?.rowReloadClosure?(MealAnalysisSetting.apiKey.rawValue)
                } catch {
                    viewController.showAlert(title: "Couldn’t Remove Key", message: error.localizedDescription)
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let value = alert.textFields?.first?.text ?? ""
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do {
                try MealAISettings.saveAPIKey(value)
                self?.rowReloadClosure?(MealAnalysisSetting.apiKey.rawValue)
            } catch {
                viewController.showAlert(title: "Couldn’t Save Key", message: error.localizedDescription)
            }
        })
        viewController.present(alert, animated: true)
    }

    private func presentModelEditor() {
        guard let viewController = viewController else { return }
        let alert = UIAlertController(
            title: "OpenAI Model",
            message: "Enter an OpenAI model ID that supports images and structured outputs through the Responses API. Changes apply to the next analysis.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = MealAISettings.model
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let value = alert.textFields?.first?.text,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            MealAISettings.model = value
            self?.rowReloadClosure?(MealAnalysisSetting.model.rawValue)
        })
        viewController.present(alert, animated: true)
    }
}
