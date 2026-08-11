import Foundation
import RokidLyricsCore

/// SDK-neutral JSON strings accepted by the verified CXR-L CustomView API.
///
/// The real transport owns SDK types. Keeping this value in the services layer
/// lets the JSON contract remain unit-testable on macOS and in simulator CI.
public struct RokidCustomViewPayload: Equatable, Sendable {
    public let openJSON: String
    public let updateJSON: String
    /// Stable identifier for layout properties that the verified update sample
    /// does not mutate. A real transport can safely close and reopen the view
    /// when this value changes instead of inventing an update command.
    public let layoutIdentifier: String

    public init(openJSON: String, updateJSON: String, layoutIdentifier: String) {
        self.openJSON = openJSON
        self.updateJSON = updateJSON
        self.layoutIdentifier = layoutIdentifier
    }
}

public enum RokidCustomViewPayloadEncodingError: Error, LocalizedError, Sendable {
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "The Rokid display payload could not be encoded as UTF-8."
        }
    }
}

/// Encodes only CustomView node types and properties exercised by Rokid's
/// official iOS sample: LinearLayout and TextView with string-valued props.
public struct RokidCustomViewPayloadEncoder: Sendable {
    public init() {}

    public func payload(for model: GlassesDisplayModel) throws -> RokidCustomViewPayload {
        let content = DisplayContent(model: model)
        let open = ViewNode(
            type: "LinearLayout",
            props: [
                "gravity": verticalGravity(for: model.preferences.verticalPosition),
                "id": NodeID.root,
                "layout_height": "match_parent",
                "layout_width": "match_parent",
                "orientation": "vertical",
                "paddingEnd": "24dp",
                "paddingStart": "24dp",
            ],
            children: [
                textNode(
                    id: NodeID.metadata,
                    text: content.metadata,
                    color: "#FF808080",
                    size: scaledSP(13, by: model.preferences.fontScale),
                    style: nil,
                    marginBottom: "18dp"
                ),
                textNode(
                    id: NodeID.previous,
                    text: content.previous,
                    color: "#FF777777",
                    size: scaledSP(16, by: model.preferences.fontScale),
                    style: nil,
                    marginBottom: "12dp"
                ),
                textNode(
                    id: NodeID.active,
                    text: content.active,
                    color: "#FFFFFFFF",
                    size: scaledSP(22, by: model.preferences.fontScale),
                    style: "bold",
                    marginBottom: "12dp"
                ),
                textNode(
                    id: NodeID.next,
                    text: content.next,
                    color: "#FFB0B0B0",
                    size: scaledSP(18, by: model.preferences.fontScale),
                    style: nil,
                    marginBottom: nil
                ),
            ]
        )

        // Updates address the stable props.id values used by the open tree.
        // Only mutable text and font size are sent; layout and emphasis remain
        // in the initial tree, minimizing traffic as lyrics advance.
        let updates = [
            UpdateOperation(
                action: "update",
                id: NodeID.metadata,
                props: [
                    "text": content.metadata,
                    "textSize": scaledSP(13, by: model.preferences.fontScale),
                ]
            ),
            UpdateOperation(
                action: "update",
                id: NodeID.previous,
                props: [
                    "text": content.previous,
                    "textSize": scaledSP(16, by: model.preferences.fontScale),
                ]
            ),
            UpdateOperation(
                action: "update",
                id: NodeID.active,
                props: [
                    "text": content.active,
                    "textSize": scaledSP(22, by: model.preferences.fontScale),
                ]
            ),
            UpdateOperation(
                action: "update",
                id: NodeID.next,
                props: [
                    "text": content.next,
                    "textSize": scaledSP(18, by: model.preferences.fontScale),
                ]
            ),
        ]

        return RokidCustomViewPayload(
            openJSON: try encode(open),
            updateJSON: try encode(updates),
            layoutIdentifier: verticalGravity(for: model.preferences.verticalPosition)
        )
    }

    private func textNode(
        id: String,
        text: String,
        color: String,
        size: String,
        style: String?,
        marginBottom: String?
    ) -> ViewNode {
        var props = [
            "gravity": "center",
            "id": id,
            "layout_height": "wrap_content",
            "layout_width": "match_parent",
            "text": text,
            "textColor": color,
            "textSize": size,
        ]
        if let style { props["textStyle"] = style }
        if let marginBottom { props["marginBottom"] = marginBottom }
        return ViewNode(type: "TextView", props: props, children: nil)
    }

    private func scaledSP(_ base: Double, by scale: Double) -> String {
        let safeScale = min(max(scale, 0.5), 2)
        return "\(Int((base * safeScale).rounded()))sp"
    }

    /// The official sample documents top/center/bottom gravity values but no
    /// pixel coordinate contract, so the abstract preference is intentionally
    /// mapped to three conservative positions rather than invented geometry.
    private func verticalGravity(for position: Double) -> String {
        switch position {
        case ..<0.34: return "top"
        case 0.67...: return "bottom"
        default: return "center_vertical"
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RokidCustomViewPayloadEncodingError.invalidUTF8
        }
        return string
    }
}

private extension RokidCustomViewPayloadEncoder {
    enum NodeID {
        static let root = "rokid_lyrics_root"
        static let metadata = "rokid_lyrics_metadata"
        static let previous = "rokid_lyrics_previous"
        static let active = "rokid_lyrics_active"
        static let next = "rokid_lyrics_next"
    }

    struct DisplayContent {
        let metadata: String
        let previous: String
        let active: String
        let next: String

        init(model: GlassesDisplayModel) {
            let title = model.trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = model.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (title.isEmpty, artist.isEmpty) {
            case (false, false): metadata = "\(title) — \(artist)"
            case (false, true): metadata = title
            case (true, false): metadata = artist
            case (true, true): metadata = ""
            }

            let preferences = model.preferences
            previous =
                preferences.visibleLineCount >= 3 && preferences.showPreviousLine
                ? model.previousLine ?? ""
                : ""
            active = model.activeLine
            next =
                preferences.visibleLineCount >= 2 && preferences.showNextLine
                ? model.nextLine ?? ""
                : ""
        }
    }

    struct ViewNode: Encodable {
        let type: String
        let props: [String: String]
        let children: [ViewNode]?
    }

    struct UpdateOperation: Encodable {
        let action: String
        let id: String
        let props: [String: String]
    }
}
