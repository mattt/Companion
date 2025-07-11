import AVFoundation
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
    static func imageContentView(data: String, mimeType: String, metadata: [String: String]?)
        -> some View
    {
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
        if let audioData = Data(base64Encoded: data) {
            AudioPlayerView(audioData: audioData, mimeType: mimeType)
        } else {
            audioDecodeErrorView()
        }
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
    private static func audioDecodeErrorView() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            Text("Unable to decode audio data")
                .font(.caption)
                .foregroundColor(.red)
        }
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

// MARK: - Audio Player View

private struct AudioPlayerView: View {
    let audioData: Data
    let mimeType: String

    @StateObject private var player = AudioPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Audio", systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .disabled(!player.isReady)

                if let errorMessage = player.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(player.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: player.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)
                }
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
        .onAppear {
            player.setupAudio(from: audioData)
        }
        .onDisappear {
            player.stop()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Player

private class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var progress: Double = 0
    @Published var errorMessage: String?

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    private static let progressUpdateInterval: TimeInterval = 0.1

    func setupAudio(from data: Data) {
        // Clean up existing resources before setting up new ones
        stop()

        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            duration = audioPlayer?.duration ?? 0
            isReady = true
            errorMessage = nil

            startTimer()
        } catch {
            let errorDescription = error.localizedDescription
            errorMessage = "Failed to load audio: \(errorDescription)"
            print("Audio setup failed: \(error)")
            isReady = false
        }
    }

    func play() {
        audioPlayer?.play()
        isPlaying = true
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentTime = 0
        progress = 0
        timer?.invalidate()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.progressUpdateInterval, repeats: true) { _ in
            guard let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
            self.progress = self.duration > 0 ? player.currentTime / self.duration : 0
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        progress = 0
    }
}
