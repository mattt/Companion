import ComposableArchitecture
import MCP
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ResourceDetailView: View {
    let store: StoreOf<ResourceDetailFeature>

    init(resource: Resource, serverId: String) {
        self.store = Store(
            initialState: ResourceDetailFeature.State(resource: resource, serverId: serverId)
        ) {
            ResourceDetailFeature()
        }
    }

    init(template: Resource.Template, serverId: String) {
        self.store = Store(
            initialState: ResourceDetailFeature.State(template: template, serverId: serverId)
        ) {
            ResourceDetailFeature()
        }
    }

    private var isTemplate: Bool {
        store.isTemplate
    }

    private var displayName: String {
        store.resource?.name ?? store.template?.name ?? ""
    }

    private var displayURI: String {
        store.resource?.uri ?? store.template?.uriTemplate ?? ""
    }

    private var displayMimeType: String? {
        store.resource?.mimeType ?? store.template?.mimeType
    }

    private var displayDescription: String? {
        store.resource?.description ?? store.template?.description
    }

    private var resourceIcon: String {
        if isTemplate {
            return "link.badge.plus"
        }

        guard let mimeType = displayMimeType else {
            return "doc"
        }

        return mimeTypeIcon(for: mimeType)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    #if os(macOS)
                        Text(displayName)
                            .font(.title)
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                    #endif

                    // Description (if available)
                    if let description = displayDescription, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // Header with Icon and Metadata
                HStack(alignment: .top, spacing: 16) {
                    // Large Icon
                    Image(systemName: resourceIcon)
                        .font(.system(size: 48))
                        .foregroundColor(isTemplate ? .orange : .blue)
                        .frame(width: 64, height: 64)
                        .background(.fill.tertiary)
                        .cornerRadius(12)
                        .draggable(
                            ResourceDragItem(
                                resource: store.resource, template: store.template, content: nil)
                        ) {
                            Image(systemName: resourceIcon)
                                .font(.system(size: 32))
                                .foregroundColor(isTemplate ? .orange : .blue)
                                .frame(width: 48, height: 48)
                                .background(.fill.tertiary)
                                .cornerRadius(8)
                        }

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        if isTemplate {
                            HStack {
                                Image(systemName: "text.bubble")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("Resource Template")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fontWeight(.medium)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 8) {
                                Image(
                                    systemName: isTemplate
                                        ? "link.badge.plus" : "link"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .center)

                                Text(displayURI)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)

                                Spacer(minLength: 8)

                                Button(action: copyURI) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.primary)
                            }

                            if let mimeType = displayMimeType {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: mimeTypeIcon(for: mimeType))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 18, alignment: .center)

                                    Text(mimeType)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)

                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                #if os(visionOS)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                #else
                    .background(.fill.tertiary)
                    .cornerRadius(12)
                #endif

                // Content Preview (only for regular resources, not templates)
                if !isTemplate {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Read Resource", systemImage: "doc.text")
                            .font(.headline)

                        if store.isReadingResource {
                            Button(action: { store.send(.cancelResourceRead) }) {
                                Label("Cancel", systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        } else {
                            Button(action: { store.send(.readResourceTapped) }) {
                                Text("Submit")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(store.serverId == nil)
                        }

                        if store.isReadingResource {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading content...")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .background(.fill.tertiary)
                            .cornerRadius(8)
                        } else if let result = store.resourceReadResult {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(
                                        "Success",
                                        systemImage: "checkmark.circle.fill"
                                    )
                                    .foregroundColor(.green)
                                    .font(.headline)

                                    Spacer()

                                    Button("Clear") {
                                        store.send(.dismissResult)
                                    }
                                    .font(.caption)
                                }

                                let content = ResourceContent(
                                    text: extractTextContent(from: result.contents),
                                    data: extractBinaryContent(from: result.contents)
                                )
                                ContentPreviewView(content: content, mimeType: displayMimeType)
                            }
                            .padding()
                            #if os(visionOS)
                                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
                            #else
                                .background(.fill.quaternary)
                                .cornerRadius(8)
                            #endif
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    #if os(visionOS)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    #else
                        .background(.fill.secondary)
                        .cornerRadius(10)
                    #endif
                } else {
                    // Template form and preview section
                    ResourceTemplateView(store: store)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(displayName)
    }

    private func copyURI() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(displayURI, forType: .string)
        #else
            UIPasteboard.general.string = displayURI
        #endif
    }

    private func extractTextContent(from contents: [Resource.Content]) -> String? {
        let textContents: [String] = contents.compactMap { content in
            if let text = content.text {
                return text
            } else if content.blob != nil {
                return "[Binary Resource: \(content.uri)]"
            }
            return nil
        }

        return textContents.isEmpty ? nil : textContents.joined(separator: "\n\n")
    }

    private func extractBinaryContent(from contents: [Resource.Content]) -> Data? {
        for content in contents {
            if let blob = content.blob {
                return Data(base64Encoded: blob)
            }
        }
        return nil
    }

    private func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func mimeTypeIcon(for mimeType: String) -> String {
        return "doc"
    }

    private func utTypeForMimeType(_ mimeType: String?) -> UTType {
        guard let mimeType = mimeType else { return .data }

        let cleanType = mimeType.lowercased()

        if cleanType.hasPrefix("image/png") {
            return .png
        } else if cleanType.hasPrefix("image/jpeg") {
            return .jpeg
        } else if cleanType.hasPrefix("image/") {
            return .image
        } else if cleanType.hasPrefix("video/") {
            return .movie
        } else if cleanType.hasPrefix("audio/") {
            return .audio
        } else if cleanType.contains("pdf") {
            return .pdf
        } else if cleanType.contains("json") {
            return .json
        } else if cleanType.contains("xml") {
            return .xml
        } else if cleanType.contains("html") {
            return .html
        } else if cleanType.contains("css") {
            return .text
        } else if cleanType.hasPrefix("text/") {
            return .plainText
        } else if cleanType.contains("zip") {
            return .zip
        } else {
            return .data
        }
    }

    private func generateFilename() -> String {
        let baseName = displayName.replacingOccurrences(of: " ", with: "_")

        guard let mimeType = displayMimeType else {
            return baseName
        }

        let cleanType = mimeType.lowercased()

        let fileExtension: String
        if cleanType.contains("json") {
            fileExtension = ".json"
        } else if cleanType.contains("xml") {
            fileExtension = ".xml"
        } else if cleanType.contains("html") {
            fileExtension = ".html"
        } else if cleanType.contains("css") {
            fileExtension = ".css"
        } else if cleanType.contains("javascript") {
            fileExtension = ".js"
        } else if cleanType.contains("typescript") {
            fileExtension = ".ts"
        } else if cleanType.hasPrefix("image/png") {
            fileExtension = ".png"
        } else if cleanType.hasPrefix("image/jpeg") {
            fileExtension = ".jpg"
        } else if cleanType.hasPrefix("image/") {
            fileExtension = ".img"
        } else if cleanType.contains("pdf") {
            fileExtension = ".pdf"
        } else if cleanType.hasPrefix("text/") {
            fileExtension = ".txt"
        } else if cleanType.contains("zip") {
            fileExtension = ".zip"
        } else {
            fileExtension = ""
        }

        return baseName + fileExtension
    }
}

// Temporary data structure for resource content
struct ResourceContent {
    let text: String?
    let data: Data?
}

// Transferable wrapper for drag and drop
struct ResourceDragItem: Transferable {
    let resource: Resource?
    let template: Resource.Template?
    let content: ResourceContent?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { item in
            return item.dragData()
        }
        .suggestedFileName { item in
            return item.filename()
        }
    }

    private func dragData() -> Data {
        // For templates, provide the URI template as text
        if let template = template {
            let uri = template.uriTemplate
            return uri.data(using: String.Encoding.utf8) ?? Data()
        }

        // For regular resources, provide the actual content
        if let content = content {
            if let text = content.text {
                return text.data(using: String.Encoding.utf8) ?? Data()
            } else if let data = content.data {
                return data
            }
        }

        // If no content is available, return empty data
        // The drag system will handle this gracefully
        return Data()
    }

    private func filename() -> String {
        return resource?.name ?? template?.name ?? "resource"
    }
}

struct ContentPreviewView: View {
    let content: ResourceContent
    let mimeType: String?
    @State private var quickLookURL: URL?
    @State private var showingQuickLook = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = content.text {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .frame(minHeight: 200, maxHeight: 400)
                .background(.fill.tertiary)
                .cornerRadius(8)
            } else if let data = content.data {
                QuickLookPreviewView(data: data, mimeType: mimeType)
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No content available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(.fill.tertiary)
                .cornerRadius(8)
            }
        }
    }
}

private struct QuickLookPreviewView: View {
    let data: Data
    let mimeType: String?
    @State private var tempURL: URL?
    @State private var showingQuickLook = false

    var body: some View {
        VStack(spacing: 12) {
            if let tempURL = tempURL {
                VStack {
                    Rectangle()
                        .fill(.fill.tertiary)
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: fileIcon)
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)

                                Text(fileTypeDescription)
                                    .font(.headline)

                                Text(
                                    ByteCountFormatter.string(
                                        fromByteCount: Int64(data.count), countStyle: .file)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)

                                Button("Preview") {
                                    showingQuickLook = true
                                }
                                .controlSize(.large)
                            }
                        }
                        .cornerRadius(8)
                }
                .quickLookPreview($tempURL, in: showingQuickLook ? [tempURL] : [])
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text("Preparing preview...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(.fill.tertiary)
                .cornerRadius(8)
            }
        }
        .onAppear {
            createTempFile()
        }
        .onDisappear {
            cleanupTempFile()
        }
    }

    private var fileIcon: String {
        guard let mimeType = mimeType else { return "doc.richtext" }

        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType.hasPrefix("video/") {
            return "video"
        } else if mimeType.hasPrefix("audio/") {
            return "music.note"
        } else if mimeType.contains("pdf") {
            return "doc.richtext.fill"
        } else if mimeType.contains("json") || mimeType.contains("xml") {
            return "curlybraces"
        } else {
            return "doc.richtext"
        }
    }

    private var fileTypeDescription: String {
        guard let mimeType = mimeType else { return "Binary Content" }

        if mimeType.hasPrefix("image/") {
            return "Image"
        } else if mimeType.hasPrefix("video/") {
            return "Video"
        } else if mimeType.hasPrefix("audio/") {
            return "Audio"
        } else if mimeType.contains("pdf") {
            return "PDF Document"
        } else if mimeType.contains("json") {
            return "JSON Data"
        } else if mimeType.contains("xml") {
            return "XML Document"
        } else {
            return mimeType.components(separatedBy: "/").last?.capitalized ?? "Binary Content"
        }
    }

    private func createTempFile() {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "mcp_resource_\(UUID().uuidString)"

        // Add file extension based on MIME type
        let fileExtension: String
        if let mimeType = mimeType {
            switch mimeType.lowercased() {
            case let type where type.contains("pdf"):
                fileExtension = ".pdf"
            case let type where type.contains("json"):
                fileExtension = ".json"
            case let type where type.contains("xml"):
                fileExtension = ".xml"
            case let type where type.hasPrefix("image/png"):
                fileExtension = ".png"
            case let type where type.hasPrefix("image/jpeg"):
                fileExtension = ".jpg"
            case let type where type.hasPrefix("image/"):
                fileExtension = ".img"
            case let type where type.hasPrefix("video/"):
                fileExtension = ".mp4"
            case let type where type.hasPrefix("audio/"):
                fileExtension = ".mp3"
            case let type where type.contains("text"):
                fileExtension = ".txt"
            default:
                fileExtension = ""
            }
        } else {
            fileExtension = ""
        }

        let fileURL = tempDirectory.appendingPathComponent(fileName + fileExtension)

        do {
            try data.write(to: fileURL)
            DispatchQueue.main.async {
                self.tempURL = fileURL
            }
        } catch {
            print("Failed to create temp file: \(error)")
        }
    }

    private func cleanupTempFile() {
        guard let tempURL = tempURL else { return }

        try? FileManager.default.removeItem(at: tempURL)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(value)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary)
                .cornerRadius(6)
        }
    }
}
