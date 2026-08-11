@preconcurrency import UIKit
import RokidLyricsServices
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController, UITextFieldDelegate {
    private let titleField = UITextField()
    private let artistField = UITextField()
    private let sourceLabel = UILabel()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private var sharedText: String?
    private var sharedURL: URL?
    private var pendingLoads = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadSharedItems()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        let heading = UILabel()
        heading.text = "Share to Rokid Lyrics"
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.adjustsFontForContentSizeCategory = true

        let explanation = UILabel()
        explanation.text = "Confirm the song details. Shared URLs are kept only as a reference; Rokid Lyrics does not inspect YouTube Music internally."
        explanation.font = .preferredFont(forTextStyle: .body)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0

        configure(field: titleField, placeholder: "Song title")
        configure(field: artistField, placeholder: "Artist")

        sourceLabel.font = .preferredFont(forTextStyle: .footnote)
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 2

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save for Rokid Lyrics"
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        saveButton.isEnabled = false

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            heading,
            explanation,
            titleField,
            artistField,
            sourceLabel,
            statusLabel,
            saveButton,
            cancelButton,
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func configure(field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.delegate = self
        field.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
    }

    private func loadSharedItems() {
        let extensionItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        sharedText = extensionItems.compactMap { $0.attributedContentText?.string }.first

        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                load(provider: provider, type: .url)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                load(provider: provider, type: .plainText)
            }
        }
        if pendingLoads == 0 { applyParsedDraft() }
    }

    private func load(provider: NSItemProvider, type: UTType) {
        pendingLoads += 1
        provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if type == .url {
                    if let url = item as? URL {
                        self.sharedURL = url
                    } else if let value = item as? String {
                        self.sharedURL = URL(string: value)
                    }
                } else if type == .plainText {
                    if let value = item as? String, !value.isEmpty {
                        self.sharedText = value
                    } else if let value = item as? NSAttributedString, !value.string.isEmpty {
                        self.sharedText = value.string
                    }
                }
                self.pendingLoads -= 1
                if self.pendingLoads == 0 { self.applyParsedDraft() }
            }
        }
    }

    private func applyParsedDraft() {
        let draft = SharedTrackParser.parse(text: sharedText, url: sharedURL)
        titleField.text = draft.title
        artistField.text = draft.artist
        sourceLabel.text = draft.url.map { "Shared link: \($0.absoluteString)" }
            ?? "No supported web link was supplied."
        statusLabel.text = draft.requiresConfirmation
            ? "Please verify or complete both fields before saving."
            : "Song details were supplied explicitly."
        updateSaveButton()
    }

    @objc private func fieldsChanged() {
        updateSaveButton()
    }

    private func updateSaveButton() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = artistField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        saveButton.isEnabled = !title.isEmpty && !artist.isEmpty
    }

    @objc private func save() {
        let draft = SharedTrackParser.parse(
            text: sharedText,
            url: sharedURL,
            explicitTitle: titleField.text,
            explicitArtist: artistField.text
        )
        saveButton.isEnabled = false
        Task {
            do {
                try await SharedTrackInbox().save(draft)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                statusLabel.textColor = .systemRed
                statusLabel.text = "Could not save the shared song: \(error.localizedDescription)"
                updateSaveButton()
            }
        }
    }

    @objc private func cancel() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: nil
        )
        extensionContext?.cancelRequest(withError: error)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === titleField {
            artistField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
}
