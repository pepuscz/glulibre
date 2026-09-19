import UIKit

final class MealCaptureCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private weak var presenter: UIViewController?
    private var completion: ((UIImage) -> Void)?

    func capture(from presenter: UIViewController, completion: @escaping (UIImage) -> Void) {
        self.presenter = presenter
        self.completion = completion

        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        presenter.present(picker, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        completion = nil
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true)
            completion = nil
            return
        }
        let handler = completion
        completion = nil
        picker.dismiss(animated: true) {
            handler?(image)
        }
    }
}

final class MealListViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var records = [MealRecord]()
    private var captureCoordinator: MealCaptureCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Meals"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "camera.fill"),
            style: .plain,
            target: self,
            action: #selector(captureMeal)
        )
        navigationItem.rightBarButtonItem?.tintColor = .systemYellow

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = .darkGray
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(MealTableViewCell.self, forCellReuseIdentifier: MealTableViewCell.reuseIdentifier)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .mealStoreDidChange, object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        records = MealStore.shared.all()
        tableView.reloadData()
        if records.isEmpty {
            let label = UILabel()
            label.text = "Tap the camera to record a meal.\nYour photo is saved before any AI analysis."
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    @objc private func captureMeal() {
        let coordinator = MealCaptureCoordinator()
        captureCoordinator = coordinator
        coordinator.capture(from: self) { [weak self] image in
            guard let self = self else { return }
            do {
                let record = try MealStore.shared.create(image: image)
                self.navigationController?.pushViewController(MealEditorViewController(recordID: record.id), animated: true)
            } catch {
                self.showAlert(title: "Couldn’t Save Photo", message: error.localizedDescription)
            }
        }
    }
}

extension MealListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { records.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 92 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: MealTableViewCell.reuseIdentifier, for: indexPath) as? MealTableViewCell else {
            return UITableViewCell()
        }
        let record = records[indexPath.row]
        cell.configure(record: record, image: MealStore.shared.image(for: record))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(MealEditorViewController(recordID: records[indexPath.row].id), animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            let alert = UIAlertController(title: "Delete Meal?", message: "This removes the photo, local meal record, and this app’s Apple Health meal entry.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                Task {
                    try? await MealHealthKitWriter.shared.deleteHealthKitMeal(for: record)
                    _ = try? MealStore.shared.delete(id: record.id)
                    await MainActor.run { completion(true) }
                }
            })
            self.present(alert, animated: true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

private final class MealTableViewCell: UITableViewCell {
    static let reuseIdentifier = "MealTableViewCell"

    private let thumbnail = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        accessoryType = .disclosureIndicator

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 8
        thumbnail.backgroundColor = .darkGray

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .systemOrange

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel, statusLabel])
        labels.axis = .vertical
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        contentView.addSubview(labels)
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 68),
            thumbnail.heightAnchor.constraint(equalToConstant: 68),
            labels.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(record: MealRecord, image: UIImage?) {
        thumbnail.image = image
        titleLabel.text = record.displayTitle
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var details = formatter.string(from: record.eatenAt)
        if let carbs = record.analysis?.nutrients.carbohydratesG {
            details += String(format: "  •  %.0f g carbs", carbs)
        }
        detailLabel.text = details
        statusLabel.text = record.status.displayName
        statusLabel.textColor = record.status == .confirmed ? .systemGreen : (record.status == .failed ? .systemRed : .systemOrange)
    }
}

final class MealEditorViewController: UIViewController, UITextFieldDelegate {
    private let recordID: UUID
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let photoView = UIImageView()
    private let eatenAtPicker = UIDatePicker()
    private let commentView = UITextView()
    private let statusLabel = UILabel()
    private let titleField = UITextField()
    private let carbsField = UITextField()
    private let proteinField = UITextField()
    private let fatField = UITextField()
    private let fiberField = UITextField()
    private let sugarField = UITextField()
    private let energyField = UITextField()
    private let summaryLabel = UILabel()
    private let itemsLabel = UILabel()
    private let uncertaintyLabel = UILabel()
    private let analyzeButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private var analysisTask: Task<Void, Never>?
    private var didPopulateFields = false

    init(recordID: UUID) {
        self.recordID = recordID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { analysisTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Meal"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveAndClose))
        setupLayout()
        populateFields()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent,
           let record = MealStore.shared.record(id: recordID),
           fieldsDiffer(from: record) {
            _ = try? persistFromFields(markConfirmedAsNeedingReview: true)
        }
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 30, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        photoView.contentMode = .scaleAspectFit
        photoView.clipsToBounds = true
        photoView.layer.cornerRadius = 12
        photoView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        photoView.heightAnchor.constraint(equalToConstant: 240).isActive = true
        contentStack.addArrangedSubview(photoView)

        let timeRow = UIStackView(arrangedSubviews: [makeLabel("Eating time", style: .body), eatenAtPicker])
        timeRow.axis = .horizontal
        timeRow.alignment = .center
        timeRow.distribution = .equalSpacing
        eatenAtPicker.datePickerMode = .dateAndTime
        eatenAtPicker.preferredDatePickerStyle = .compact
        contentStack.addArrangedSubview(timeRow)

        contentStack.addArrangedSubview(makeSectionLabel("Your comment"))
        let commentHelp = makeLabel("Optional: ingredients, quantity, preparation, drink, or how much you ate. Dictation works here too.", style: .footnote)
        commentHelp.textColor = .secondaryLabel
        commentHelp.numberOfLines = 0
        contentStack.addArrangedSubview(commentHelp)

        styleTextView(commentView)
        commentView.heightAnchor.constraint(equalToConstant: 92).isActive = true
        contentStack.addArrangedSubview(commentView)

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)

        configurePrimaryButton(analyzeButton, title: "Analyze photo & comment", action: #selector(analyze))
        contentStack.addArrangedSubview(analyzeButton)
        let privacy = makeLabel("The photo and comment are sent to OpenAI only when you tap Analyze. The original remains on this iPhone.", style: .caption1)
        privacy.textColor = .secondaryLabel
        privacy.numberOfLines = 0
        contentStack.addArrangedSubview(privacy)

        contentStack.addArrangedSubview(makeSectionLabel("Review the estimate"))
        styleTextField(titleField, placeholder: "Meal name", keyboard: .default)
        contentStack.addArrangedSubview(titleField)

        let firstNutrients = makeNutrientRow(("Carbs (g)", carbsField), ("Protein (g)", proteinField))
        let secondNutrients = makeNutrientRow(("Fat (g)", fatField), ("Fiber (g)", fiberField))
        let thirdNutrients = makeNutrientRow(("Sugar (g)", sugarField), ("Energy (kcal)", energyField))
        contentStack.addArrangedSubview(firstNutrients)
        contentStack.addArrangedSubview(secondNutrients)
        contentStack.addArrangedSubview(thirdNutrients)

        summaryLabel.numberOfLines = 0
        summaryLabel.textColor = .white
        summaryLabel.font = .preferredFont(forTextStyle: .body)
        itemsLabel.numberOfLines = 0
        itemsLabel.textColor = .secondaryLabel
        itemsLabel.font = .preferredFont(forTextStyle: .subheadline)
        uncertaintyLabel.numberOfLines = 0
        uncertaintyLabel.textColor = .systemOrange
        uncertaintyLabel.font = .preferredFont(forTextStyle: .footnote)
        contentStack.addArrangedSubview(summaryLabel)
        contentStack.addArrangedSubview(itemsLabel)
        contentStack.addArrangedSubview(uncertaintyLabel)

        configurePrimaryButton(confirmButton, title: "Confirm meal", action: #selector(confirmMeal))
        confirmButton.backgroundColor = .systemGreen
        contentStack.addArrangedSubview(confirmButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func populateFields() {
        guard !didPopulateFields, let record = MealStore.shared.record(id: recordID) else { return }
        didPopulateFields = true
        photoView.image = MealStore.shared.image(for: record)
        eatenAtPicker.date = record.eatenAt
        commentView.text = record.userComment
        applyAnalysis(record.analysis)
        updateStatus(record)
    }

    private func applyAnalysis(_ analysis: MealAnalysis?) {
        titleField.text = analysis?.title
        setNumber(analysis?.nutrients.carbohydratesG, in: carbsField)
        setNumber(analysis?.nutrients.proteinG, in: proteinField)
        setNumber(analysis?.nutrients.fatG, in: fatField)
        setNumber(analysis?.nutrients.fiberG, in: fiberField)
        setNumber(analysis?.nutrients.sugarG, in: sugarField)
        setNumber(analysis?.nutrients.energyKcal, in: energyField)
        summaryLabel.text = analysis?.summary
        itemsLabel.text = analysis?.items.map { "• \($0.name) — \($0.portion)" }.joined(separator: "\n")

        guard let analysis = analysis else {
            uncertaintyLabel.text = "AI estimates can miss portion size, oils, sauces, and hidden ingredients."
            confirmButton.isEnabled = false
            confirmButton.alpha = 0.45
            return
        }

        var notes = [String(format: "Overall confidence: %.0f%%", analysis.overallConfidence * 100)]
        if !analysis.assumptions.isEmpty {
            notes.append("Assumptions: " + analysis.assumptions.joined(separator: "; "))
        }
        if !analysis.questions.isEmpty {
            notes.append("Helpful details: " + analysis.questions.joined(separator: " "))
        }
        uncertaintyLabel.text = notes.joined(separator: "\n")
        confirmButton.isEnabled = true
        confirmButton.alpha = 1
    }

    private func updateStatus(_ record: MealRecord) {
        var text = record.status.displayName
        if let error = record.analysisError, !error.isEmpty { text += "\n" + error }
        statusLabel.text = text
        statusLabel.textColor = record.status == .confirmed ? .systemGreen : (record.status == .failed ? .systemRed : .systemOrange)
        analyzeButton.isEnabled = record.status != .analyzing
        analyzeButton.setTitle(record.status == .analyzing ? "Analyzing…" : "Analyze photo & comment", for: .normal)
    }

    @objc private func analyze() {
        dismissKeyboard()
        guard let current = try? persistFromFields(markConfirmedAsNeedingReview: true), let image = MealStore.shared.image(for: current) else {
            showAlert(title: "Couldn’t Save Meal", message: "The meal or its photograph is unavailable.")
            return
        }

        guard MealAISettings.hasAPIKey else {
            presentAPIKeyPrompt { [weak self] saved in
                if saved { self?.analyze() }
            }
            return
        }

        var analyzingRecord = current
        analyzingRecord.status = .analyzing
        analyzingRecord.analysisError = nil
        try? MealStore.shared.save(analyzingRecord)
        updateStatus(analyzingRecord)

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let analysis = try await MealAIClient().analyze(image: image, userComment: analyzingRecord.userComment)
                guard !Task.isCancelled else { return }
                var completed = MealStore.shared.record(id: self.recordID) ?? analyzingRecord
                completed.analysis = analysis
                completed.status = .estimated
                completed.analysisError = nil
                try MealStore.shared.save(completed)
                await MainActor.run {
                    self.applyAnalysis(analysis)
                    self.updateStatus(completed)
                }
            } catch {
                guard !Task.isCancelled else { return }
                var failed = MealStore.shared.record(id: self.recordID) ?? analyzingRecord
                failed.status = failed.analysis == nil ? .failed : .estimated
                failed.analysisError = error.localizedDescription
                try? MealStore.shared.save(failed)
                await MainActor.run {
                    self.updateStatus(failed)
                    self.showAlert(title: "Analysis Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func confirmMeal() {
        dismissKeyboard()
        guard var record = try? persistFromFields(markConfirmedAsNeedingReview: false), record.analysis != nil else { return }
        record.status = .confirmed
        record.analysisError = nil
        record.revision += 1
        do {
            try MealStore.shared.save(record)
        } catch {
            showAlert(title: "Couldn’t Save Meal", message: error.localizedDescription)
            return
        }
        updateStatus(record)

        guard MealAISettings.writeConfirmedMealsToHealthKit else {
            showAlert(title: "Meal Confirmed", message: "Saved locally. Apple Health export is disabled in Settings.")
            return
        }

        confirmButton.isEnabled = false
        confirmButton.setTitle("Saving to Apple Health…", for: .normal)
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let uuid = try await MealHealthKitWriter.shared.replaceHealthKitMeal(for: record)
                var saved = MealStore.shared.record(id: self.recordID) ?? record
                saved.healthKitCorrelationUUID = uuid
                try MealStore.shared.save(saved)
                await MainActor.run {
                    self.confirmButton.isEnabled = true
                    self.confirmButton.setTitle("Confirmed in Apple Health", for: .normal)
                    self.showAlert(title: "Meal Confirmed", message: "The photo and comment are saved locally, and the nutrition estimate is now in Apple Health.")
                }
            } catch {
                await MainActor.run {
                    self.confirmButton.isEnabled = true
                    self.confirmButton.setTitle("Confirm meal", for: .normal)
                    self.showAlert(title: "Saved Locally", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func saveAndClose() {
        do {
            let existing = MealStore.shared.record(id: recordID)
            let changed = existing.map { fieldsDiffer(from: $0) } ?? true
            _ = try persistFromFields(markConfirmedAsNeedingReview: changed)
            navigationController?.popViewController(animated: true)
        } catch {
            showAlert(title: "Couldn’t Save Meal", message: error.localizedDescription)
        }
    }

    @discardableResult
    private func persistFromFields(markConfirmedAsNeedingReview: Bool) throws -> MealRecord {
        guard var record = MealStore.shared.record(id: recordID) else { throw MealEditorError.missingRecord }
        record.eatenAt = eatenAtPicker.date
        record.timeZoneIdentifier = TimeZone.current.identifier
        record.userComment = commentView.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let nutrients = MealNutrients(
            carbohydratesG: number(from: carbsField),
            proteinG: number(from: proteinField),
            fatG: number(from: fatField),
            fiberG: number(from: fiberField),
            sugarG: number(from: sugarField),
            energyKcal: number(from: energyField)
        )
        let cleanTitle = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if record.analysis != nil || nutrients.hasAnyValue || !cleanTitle.isEmpty {
            let old = record.analysis
            record.analysis = MealAnalysis(
                title: cleanTitle.isEmpty ? (old?.title ?? "Meal") : cleanTitle,
                summary: old?.summary ?? "Entered by user.",
                items: old?.items ?? [],
                nutrients: nutrients,
                overallConfidence: old?.overallConfidence ?? 1,
                assumptions: old?.assumptions ?? [],
                questions: old?.questions ?? [],
                model: old?.model ?? "manual",
                analyzedAt: old?.analyzedAt ?? Date()
            )
        }
        if markConfirmedAsNeedingReview && record.status == .confirmed {
            record.status = .estimated
        }
        try MealStore.shared.save(record)
        return record
    }

    private func presentAPIKeyPrompt(completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "OpenAI API Key",
            message: "Stored only in this iPhone’s Keychain. You can change or remove it later in Settings › Meal Photos & AI.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "sk-..."
            field.isSecureTextEntry = true
            field.textContentType = .password
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            do {
                try MealAISettings.saveAPIKey(alert.textFields?.first?.text ?? "")
                completion(MealAISettings.hasAPIKey)
            } catch {
                self.showAlert(title: "Couldn’t Save Key", message: error.localizedDescription)
                completion(false)
            }
        })
        present(alert, animated: true)
    }

    private func makeNutrientRow(_ first: (String, UITextField), _ second: (String, UITextField)) -> UIStackView {
        let firstStack = makeFieldStack(label: first.0, field: first.1)
        let secondStack = makeFieldStack(label: second.0, field: second.1)
        let row = UIStackView(arrangedSubviews: [firstStack, secondStack])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private func makeFieldStack(label: String, field: UITextField) -> UIStackView {
        styleTextField(field, placeholder: "Unknown", keyboard: .decimalPad)
        let labelView = makeLabel(label, style: .caption1)
        labelView.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [labelView, field])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    private func styleTextField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.borderStyle = .roundedRect
        field.backgroundColor = UIColor(white: 0.16, alpha: 1)
        field.textColor = .white
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func styleTextView(_ textView: UITextView) {
        textView.backgroundColor = UIColor(white: 0.16, alpha: 1)
        textView.textColor = .white
        textView.font = .preferredFont(forTextStyle: .body)
        textView.layer.cornerRadius = 9
        textView.layer.borderColor = UIColor.darkGray.cgColor
        textView.layer.borderWidth = 0.5
    }

    private func configurePrimaryButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.backgroundColor = .systemYellow
        button.layer.cornerRadius = 10
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = makeLabel(text, style: .headline)
        label.textColor = .white
        return label
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        return label
    }

    private func setNumber(_ value: Double?, in field: UITextField) {
        guard let value = value else { field.text = nil; return }
        field.text = String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }

    private func number(from field: UITextField) -> Double? {
        guard let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let value = Double(text.replacingOccurrences(of: ",", with: "."))
        guard let value = value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func fieldsDiffer(from record: MealRecord) -> Bool {
        if abs(record.eatenAt.timeIntervalSince(eatenAtPicker.date)) > 1 { return true }
        if record.userComment != commentView.text.trimmingCharacters(in: .whitespacesAndNewlines) { return true }

        let old = record.analysis
        let cleanTitle = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if (old?.title ?? "") != cleanTitle { return true }

        let pairs: [(Double?, Double?)] = [
            (old?.nutrients.carbohydratesG, number(from: carbsField)),
            (old?.nutrients.proteinG, number(from: proteinField)),
            (old?.nutrients.fatG, number(from: fatField)),
            (old?.nutrients.fiberG, number(from: fiberField)),
            (old?.nutrients.sugarG, number(from: sugarField)),
            (old?.nutrients.energyKcal, number(from: energyField))
        ]
        return pairs.contains { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): return false
            case let (lhs?, rhs?): return abs(lhs - rhs) > 0.0001
            default: return true
            }
        }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private enum MealEditorError: LocalizedError {
    case missingRecord
    var errorDescription: String? { "The local meal record is missing." }
}

extension UIViewController {
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
