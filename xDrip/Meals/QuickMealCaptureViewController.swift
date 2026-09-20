import AVFoundation
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import UIKit

private final class MealCamera: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "MealCamera.session")
    var result: ((Result<UIImage, Error>) -> Void)?

    func start(completion: @escaping (Bool) -> Void) {
        queue.async {
            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input),
                      self.session.canAddOutput(self.output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { completion(false) }; return
                }
                self.session.addInput(input); self.session.addOutput(self.output)
                self.session.commitConfiguration()
            }
            self.session.startRunning()
            DispatchQueue.main.async { completion(self.session.isRunning) }
        }
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func capture() {
        queue.async {
            guard self.session.isRunning else { return }
            if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let value: Result<UIImage, Error>
        if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) { value = .success(image) }
        else { value = .failure(error ?? MealAIError.imageEncodingFailed) }
        DispatchQueue.main.async { self.result?(value) }
    }
}

/// Shutter → saved photo → optional autosaved note. No analysis or confirmation gate.
final class QuickMealCaptureViewController: UIViewController, UITextViewDelegate, PHPickerViewControllerDelegate {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    private let camera = MealCamera()
    private var preview: AVCaptureVideoPreviewLayer!
    private let photo = UIImageView()
    private let stage = UIView()
    private let note = UITextView()
    private let status = UILabel()
    private let shutter = UIButton(type: .system)
    private let library = UIButton(type: .system)
    private let captureControls = UIStackView()
    private let contentScroll = UIScrollView()
    private var noteHeight: NSLayoutConstraint?
    private let eatenAtPicker = UIDatePicker()
    private let timeRow = UIStackView()
    private let cameraSettings = UIButton(type: .system)
    private var imported = false
    private var recordID: UUID?
    private let captureID = UUID()
    private var capturedAt = Date()
    private var saving = false
    private var unsavedImage: UIImage?
    private var foregroundObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Meal photo"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.finish() })
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Close camera"
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.keyboardDismissMode = .interactive
        view.addSubview(contentScroll)
        contentScroll.addSubview(stack)
        NSLayoutConstraint.activate([
            contentScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: contentScroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        stage.backgroundColor = .black; stage.layer.cornerRadius = 24; stage.clipsToBounds = true
        stack.addArrangedSubview(stage)
        let height = stage.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42)
        height.priority = .defaultHigh; height.isActive = true
        stage.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        preview = AVCaptureVideoPreviewLayer(session: camera.session); preview.videoGravity = .resizeAspectFill
        stage.layer.addSublayer(preview)
        photo.contentMode = .scaleAspectFit; photo.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(photo)
        NSLayoutConstraint.activate([photo.leadingAnchor.constraint(equalTo: stage.leadingAnchor), photo.trailingAnchor.constraint(equalTo: stage.trailingAnchor), photo.topAnchor.constraint(equalTo: stage.topAnchor), photo.bottomAnchor.constraint(equalTo: stage.bottomAnchor)])
        status.font = .preferredFont(forTextStyle: .subheadline); status.adjustsFontForContentSizeCategory = true
        status.textColor = .secondaryLabel; status.numberOfLines = 0
        stack.addArrangedSubview(status)
        let timeLabel = UILabel(); timeLabel.text = "Eaten at"; timeLabel.font = .preferredFont(forTextStyle: .subheadline)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        eatenAtPicker.datePickerMode = .dateAndTime; eatenAtPicker.preferredDatePickerStyle = .compact
        eatenAtPicker.maximumDate = Date(); eatenAtPicker.accessibilityLabel = "Eating time"
        eatenAtPicker.addAction(UIAction { [weak self] _ in self?.saveEatingTime() }, for: .valueChanged)
        timeRow.axis = .vertical; timeRow.alignment = .leading; timeRow.spacing = 6
        timeRow.addArrangedSubview(timeLabel); timeRow.addArrangedSubview(eatenAtPicker)
        timeRow.isHidden = true; stack.addArrangedSubview(timeRow)
        cameraSettings.setTitle("Open camera settings", for: .normal)
        cameraSettings.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        cameraSettings.isHidden = true; stack.addArrangedSubview(cameraSettings)
        note.delegate = self; note.font = .preferredFont(forTextStyle: .body); note.adjustsFontForContentSizeCategory = true
        note.backgroundColor = .secondarySystemBackground; note.layer.cornerRadius = 14
        note.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        note.accessibilityLabel = "Optional meal note"
        noteHeight = note.heightAnchor.constraint(equalToConstant: 84)
        noteHeight?.isActive = true
        note.isHidden = true; stack.addArrangedSubview(note)
        captureControls.addArrangedSubview(library); captureControls.addArrangedSubview(shutter)
        captureControls.distribution = .fillEqually; captureControls.spacing = 20
        library.configuration = .tinted(); library.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        library.accessibilityLabel = "Choose a photo"
        library.addAction(UIAction { [weak self] _ in self?.choosePhoto() }, for: .touchUpInside)
        shutter.configuration = .filled(); shutter.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        shutter.accessibilityLabel = "Take meal photo"; shutter.isEnabled = false
        shutter.addAction(UIAction { [weak self] _ in self?.takePhoto() }, for: .touchUpInside)
        let controlsHeight = captureControls.heightAnchor.constraint(equalToConstant: 64)
        controlsHeight.priority = .defaultHigh; controlsHeight.isActive = true
        stack.addArrangedSubview(captureControls)
        camera.result = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let image): self.save(image)
            case .failure: self.saving = false; self.shutter.isEnabled = true; self.library.isEnabled = true; self.status.text = "Couldn’t take photo. Try again."
            }
        }
        configureCamera()
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                MealAnalysisService.shared.hold(self.captureID)
                if self.recordID == nil && self.unsavedImage == nil { self.configureCamera() }
            }
        }
    }

    deinit { if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) } }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let readableNoteHeight = max(84, (note.font?.lineHeight ?? 20) * 2 + 24)
        if noteHeight?.constant != readableNoteHeight { noteHeight?.constant = readableNoteHeight }
        preview.frame = stage.bounds
        if preview.connection?.isVideoOrientationSupported == true { preview.connection?.videoOrientation = .portrait }
        if note.isFirstResponder { contentScroll.scrollRectToVisible(note.convert(note.bounds, to: contentScroll), animated: false) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed == true || isBeingDismissed {
            camera.stop()
            if let recordID { MealAnalysisService.shared.release(recordID) }
        }
    }

    private func configureCamera() {
        cameraSettings.isHidden = true
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { status.text = "Choose a photo from your library."; return }
        let start = { [weak self] in
            self?.camera.start { [weak self] ready in
                self?.shutter.isEnabled = ready
                self?.status.text = ready ? nil : "Camera unavailable. Choose a photo instead."
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { if allowed { start() } else { self?.status.text = "Camera access is off. You can choose a photo."; self?.cameraSettings.isHidden = false } }
            }
        default: status.text = "Camera access is off. You can choose a photo."; cameraSettings.isHidden = false
        }
    }

    private func takePhoto() {
        guard !saving else { return }
        if let image = unsavedImage { save(image); return }
        saving = true; imported = false; capturedAt = Date(); eatenAtPicker.maximumDate = capturedAt; eatenAtPicker.date = capturedAt
        shutter.isEnabled = false; library.isEnabled = false
        camera.capture()
    }

    private func save(_ image: UIImage) {
        saving = true; unsavedImage = image; shutter.isEnabled = false; library.isEnabled = false
        navigationController?.isModalInPresentation = true
        navigationItem.leftBarButtonItem?.isEnabled = false
        photo.image = image; camera.stop(); status.text = "Saving…"
        let date = capturedAt, eatingTime = eatenAtPicker.date, shouldAnalyze = MealAISettings.shouldAnalyzeNewMeals, id = captureID
        MealAnalysisService.shared.hold(id)
        Task { [weak self] in
            do {
                // The brief disk commit runs off the UI thread. AI is not on the capture path.
                let record = try await Task.detached(priority: .userInitiated) {
                    try MealStore.shared.create(image: image, capturedAt: date, requestAnalysis: shouldAnalyze, id: id, eatenAt: eatingTime)
                }.value
                guard let self else { return }
                self.recordID = record.id; self.unsavedImage = nil; self.saving = false
                self.title = "Saved"
                self.status.text = self.imported ? "Photo saved · check eating time" : "Add a note · optional"
                self.timeRow.isHidden = false; self.cameraSettings.isHidden = true
                self.note.isHidden = false; self.captureControls.isHidden = true
                self.navigationItem.leftBarButtonItem = nil
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.finish() })
                self.navigationController?.isModalInPresentation = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                guard let self else { return }
                self.saving = false; self.shutter.isEnabled = true
                self.shutter.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
                self.shutter.accessibilityLabel = "Retry saving photo"
                self.navigationItem.leftBarButtonItem?.isEnabled = true
                self.status.text = "Photo not saved. Tap retry."
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        _ = saveCaptureEdits()
    }

    /// A successful note write must never mask a failed eating-time write (or vice versa).
    @discardableResult private func saveCaptureEdits() -> Bool {
        guard let recordID else { return true }
        do {
            let comment = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldAnalyze = MealAISettings.shouldAnalyzeNewMeals
            let saved = try MealStore.shared.update(id: recordID) {
                let changedNote = $0.userComment != comment
                $0.userComment = comment
                $0.eatenAt = eatenAtPicker.date
                if changedNote && shouldAnalyze {
                    $0.analysisRequestID = UUID(); $0.analysisAttempts = 0; $0.analysisRetryAfter = nil
                    $0.status = .draft; $0.analysisError = nil
                }
            }
            guard saved != nil else { throw MealStoreError.unavailable("This meal is no longer in your journal.") }
            status.text = "Saved"
            navigationController?.isModalInPresentation = false
            return true
        } catch {
            status.text = "Changes not saved. Try Done again."
            navigationController?.isModalInPresentation = true
            return false
        }
    }

    private func finish() {
        guard !saving else { return }
        if let recordID {
            guard saveCaptureEdits() else { return }
            MealAnalysisService.shared.release(recordID)
        }
        MealAnalysisService.shared.release(captureID)
        camera.stop(); dismiss(animated: true)
    }

    private func choosePhoto() {
        var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true) { [weak self] in
            guard let self, let provider = results.first?.itemProvider else { return }
            self.imported = true; self.capturedAt = Date()
            let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
                let image = data.flatMap { UIImage(data: $0) }
                let date = data.flatMap { Self.photoDate($0) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.eatenAtPicker.maximumDate = Date()
                    self.eatenAtPicker.date = date ?? self.capturedAt
                    if let image { self.save(image) }
                    else { self.status.text = "Photo unavailable. Choose another." }
                }
            }
        }
    }

    private func saveEatingTime() {
        _ = saveCaptureEdits()
    }

    nonisolated private static func photoDate(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return nil }
        return MealPhotoTime.date(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
                                  offset: exif["OffsetTimeOriginal"] as? String, now: Date())
    }

    #if DEBUG && targetEnvironment(simulator)
    func showSavedPreview(_ record: MealRecord) {
        loadViewIfNeeded(); recordID = record.id; photo.image = MealStore.shared.image(for: record)
        title = "Saved"; status.text = "Add a note · optional"; note.isHidden = false
        eatenAtPicker.date = record.eatenAt; timeRow.isHidden = false
        note.text = record.userComment; captureControls.isHidden = true
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.finish() })
    }
    #endif
}
