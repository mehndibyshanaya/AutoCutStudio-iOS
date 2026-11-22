import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

// Import the movie as a file. This avoids loading a 4K video into RAM.
private struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let source = received.file
            let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("AutoCut_Input_\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var inputURL: URL?
    @State private var player: AVPlayer?
    @State private var videoName = "No video selected"
    @State private var duration: Double = 0
    @State private var resolution = ""
    @State private var frameRate = ""
    @State private var interval: Double = 2.0
    @State private var keepFirst = true
    @State private var exporting = false
    @State private var progress: Double = 0
    @State private var status = "Choose a video to start."
    @State private var outputURL: URL?
    @State private var showShare = false
    @State private var errorMessage = ""
    @State private var showError = false

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.96)
    private let panel = Color(red: 0.105, green: 0.12, blue: 0.15)

    private var sectionCount: Int {
        duration > 0 ? Int(ceil(duration / interval)) : 0
    }

    private var estimatedOutputDuration: Double {
        guard sectionCount > 0 else { return 0 }
        return (0..<sectionCount).reduce(0.0) { total, index in
            let start = Double(index) * interval
            let length = min(interval, max(0, duration - start))
            let keep = keepFirst ? index.isMultiple(of: 2) : !index.isMultiple(of: 2)
            return total + (keep ? length : 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    header
                    videoCard
                    if duration > 0 {
                        timelineCard
                    }
                    intervalCard
                    patternCard
                    exportCard

                    Label(
                        "Processing happens on this iPhone. Your original video is not modified.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.045, green: 0.052, blue: 0.067).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .onChange(of: selectedItem) { item in
                Task {
                    await loadVideo(item)
                }
            }
            .sheet(isPresented: $showShare) {
                if let outputURL = outputURL {
                    ShareSheet(items: [outputURL])
                        .presentationDetents([.medium, .large])
                }
            }
            .alert("AutoCut Studio", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("AutoCut Studio")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Fast alternating video cutter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                HStack(spacing: 14) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inputURL == nil ? "Choose video" : "Change video")
                            .font(.headline)
                            .foregroundStyle(accent)
                        Text(videoName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(panel)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .disabled(exporting)

            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 205)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                HStack {
                    Label(formatTime(duration), systemImage: "clock")
                    Spacer()
                    Text(resolution)
                    if !frameRate.isEmpty {
                        Text(frameRate)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cut preview")
                    .font(.headline)
                Spacer()
                Text("\(sectionCount) sections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<sectionCount, id: \.self) { index in
                        let keep = keepFirst ? index.isMultiple(of: 2) : !index.isMultiple(of: 2)
                        Rectangle()
                            .fill(keep ? accent : Color.gray.opacity(0.35))
                            .frame(width: max(2, (geometry.size.width - CGFloat(max(0, sectionCount - 1)) * 2) / CGFloat(max(1, sectionCount))))
                    }
                }
            }
            .frame(height: 18)
            .clipShape(Capsule())

            HStack {
                Text("Original: \(formatTime(duration))")
                Spacer()
                Text("Output: ~\(formatTime(estimatedOutputDuration))")
                    .foregroundStyle(accent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clip interval")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f sec", interval))
                    .font(.headline)
                    .foregroundStyle(accent)
            }

            Slider(value: $interval, in: 0.5...10, step: 0.1)
                .tint(accent)
                .disabled(exporting)

            Text("Each kept or removed section uses this duration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var patternCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cutting mode")
                .font(.headline)

            modeRow(
                title: "Keep alternate clips",
                subtitle: "Keep 1st, remove 2nd, keep 3rd…",
                selected: keepFirst
            ) {
                keepFirst = true
            }

            modeRow(
                title: "Remove alternate clips",
                subtitle: "Remove 1st, keep 2nd, remove 3rd…",
                selected: !keepFirst
            ) {
                keepFirst = false
            }
        }
        .padding(18)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func modeRow(
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? accent : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.opacity(0.13) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(exporting)
    }

    private var exportCard: some View {
        VStack(spacing: 13) {
            Button {
                Task {
                    await exportVideo()
                }
            } label: {
                HStack {
                    Text(exporting ? "Exporting…" : "Export edited video")
                    Spacer()
                    Image(systemName: "scissors")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(19)
                .background(inputURL == nil || exporting ? Color.gray : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .disabled(inputURL == nil || exporting)

            if exporting {
                ProgressView(value: progress)
                    .tint(accent)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if outputURL != nil {
                Button {
                    showShare = true
                } label: {
                    Label("Save or share finished video", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(17)
                        .background(Color.green.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(exporting)
            }
        }
        .padding(18)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    @MainActor
    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        status = "Importing video…"
        outputURL = nil

        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                throw AutoCutError.importFailed
            }

            inputURL = movie.url
            videoName = movie.url.lastPathComponent

            let asset = AVURLAsset(url: movie.url)
            let assetDuration = asset.duration.seconds
            guard assetDuration.isFinite, assetDuration > 0 else {
                throw AutoCutError.invalidDuration
            }
            duration = assetDuration

            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                resolution = "\(Int(abs(size.width))) × \(Int(abs(size.height)))"
                let fps = track.nominalFrameRate
                frameRate = fps > 0 ? "\(Int(fps.rounded())) FPS" : ""
            } else {
                resolution = ""
                frameRate = ""
            }

            player = AVPlayer(url: movie.url)
            status = "Video ready. Choose your cutting mode and export."
        } catch {
            status = "Could not import the video."
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func exportVideo() async {
        guard let inputURL = inputURL else { return }
        guard duration > 0 else { return }

        exporting = true
        progress = 0
        outputURL = nil
        status = "Preparing video…"

        do {
            let asset = AVURLAsset(url: inputURL)
            let composition = AVMutableComposition()

            guard let sourceVideo = asset.tracks(withMediaType: .video).first,
                  let destinationVideo = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                throw AutoCutError.noVideoTrack
            }

            let sourceAudio = asset.tracks(withMediaType: .audio).first
            let destinationAudio = sourceAudio == nil ? nil : composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )

            let scale: CMTimeScale = 600
            let total = CMTime(seconds: duration, preferredTimescale: scale)
            var insertionTime = CMTime.zero
            let count = Int(ceil(duration / interval))

            for index in 0..<count {
                let startSeconds = Double(index) * interval
                let endSeconds = min(duration, startSeconds + interval)
                let keep = keepFirst ? index.isMultiple(of: 2) : !index.isMultiple(of: 2)

                if keep && endSeconds > startSeconds {
                    let start = CMTime(seconds: startSeconds, preferredTimescale: scale)
                    let end = CMTime(seconds: endSeconds, preferredTimescale: scale)
                    let range = CMTimeRange(start: start, end: end)

                    try destinationVideo.insertTimeRange(range, of: sourceVideo, at: insertionTime)
                    if let sourceAudio = sourceAudio, let destinationAudio = destinationAudio {
                        let audioDuration = min(end, sourceAudio.timeRange.end).seconds - start.seconds
                        if audioDuration > 0 {
                            let audioRange = CMTimeRange(
                                start: start,
                                duration: CMTime(seconds: audioDuration, preferredTimescale: scale)
                            )
                            try destinationAudio.insertTimeRange(audioRange, of: sourceAudio, at: insertionTime)
                        }
                    }
                    insertionTime = CMTimeAdd(insertionTime, range.duration)
                }
            }

            guard insertionTime.seconds > 0 else {
                throw AutoCutError.emptyOutput
            }

            // Preserve source orientation. Passthrough is fast and avoids generation loss,
            // but compressed-video cuts may be limited by keyframes.
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("AutoCut_\(UUID().uuidString).mov")
            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            ) else {
                throw AutoCutError.exportUnavailable
            }

            exporter.outputURL = output
            exporter.outputFileType = .mov
            exporter.shouldOptimizeForNetworkUse = false

            status = "Exporting in original encoded quality…"
            try await runExport(exporter)

            outputURL = output
            progress = 1
            status = "Export complete. Your original video is unchanged."
        } catch {
            status = "Export failed."
            errorMessage = error.localizedDescription
            showError = true
        }

        exporting = false
    }

    @MainActor
    private func runExport(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exporter.error ?? AutoCutError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: AutoCutError.exportCancelled)
                default:
                    continuation.resume(throwing: exporter.error ?? AutoCutError.exportFailed)
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds.rounded()))
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }
}

private enum AutoCutError: LocalizedError {
    case importFailed
    case invalidDuration
    case noVideoTrack
    case emptyOutput
    case exportUnavailable
    case exportFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .importFailed: return "The selected video could not be imported."
        case .invalidDuration: return "The selected video has an invalid duration."
        case .noVideoTrack: return "No video track was found in this file."
        case .emptyOutput: return "The selected cutting pattern produced an empty video."
        case .exportUnavailable: return "iOS could not create an export session for this video."
        case .exportFailed: return "The video export failed. Try another video or cutting interval."
        case .exportCancelled: return "The video export was cancelled."
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
