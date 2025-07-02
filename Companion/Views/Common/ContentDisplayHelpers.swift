import SwiftUI

// MARK: - Shared Content Display Views

struct ContentDisplayHelpers {
    
    @ViewBuilder
    static func textContentView(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(visionOS)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                #else
                    .background(.fill.tertiary)
                    .cornerRadius(8)
                #endif
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    static func imageContentView(data: String, mimeType: String, metadata: [String: String]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Image", systemImage: "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let imageData = Data(base64Encoded: data) {
                #if os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(8)
                    } else {
                        imageDecodeErrorView()
                    }
                #else
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(8)
                    } else {
                        imageDecodeErrorView()
                    }
                #endif
            } else {
                imageDecodeErrorView()
            }

            if let metadata = metadata, !metadata.isEmpty {
                metadataView(metadata)
            }
        }
        .padding()
        #if os(visionOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        #else
            .background(.fill.tertiary)
            .cornerRadius(8)
        #endif
    }

    @ViewBuilder
    static func audioContentView(data: String, mimeType: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Audio", systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.accentColor)
                Text("Audio content available")
                    .font(.body)
                Spacer()
                Text("\(data.count) bytes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            #if os(visionOS)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            #else
                .background(.fill.quaternary)
                .cornerRadius(6)
            #endif
        }
        .padding()
        #if os(visionOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        #else
            .background(.fill.tertiary)
            .cornerRadius(8)
        #endif
    }

    @ViewBuilder
    static func resourceContentView(uri: String, mimeType: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Resource", systemImage: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !mimeType.isEmpty {
                    Text(mimeType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(uri)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.accentColor)
                .textSelection(.enabled)

            if let text = text, !text.isEmpty {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding()
        #if os(visionOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        #else
            .background(.fill.tertiary)
            .cornerRadius(8)
        #endif
    }

    @ViewBuilder
    private static func imageDecodeErrorView() -> some View {
        Text("Failed to decode image data")
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            #if os(visionOS)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            #else
                .background(.fill.tertiary)
                .cornerRadius(8)
            #endif
    }

    @ViewBuilder
    private static func metadataView(_ metadata: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata:")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                HStack {
                    Text(key)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(metadata[key] ?? "")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        #if os(visionOS)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        #else
            .background(.fill.quaternary)
            .cornerRadius(6)
        #endif
    }
}
