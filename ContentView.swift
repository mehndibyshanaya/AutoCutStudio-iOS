import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var inputURL: URL?
    @State private var videoName = "No video selected"
    @State private var interval = 2.0
    @State private var keepFirst = true
    @State private var isExporting = false
    @State private var progress = 0.0
    @State private var status = "Choose a video to begin."
    @State private var outputURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AutoCut Studio")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Alternating video cutter")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    PhotosPicker(selection: $selectedItem, matching: .videos) {
                        HStack(spacing: 14) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 28))
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Choose video")
                                    .font(.headline)
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
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(isExporting)
                    .onChange(of: selectedItem) { item in
    Task {
        await loadVideo(item)
    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Clip interval")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1f sec", interval))
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.cyan)
                        }
                        Slider(value: $interval, in: 0.2...30, step: 0.1)
                            .tint(.cyan)
                        Text("Each kept or removed section uses this duration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cutting mode")
                            .font(.headline)
                        modeButton(title: "Keep alternate clips", detail: "Keep 1st, remove 2nd, keep 3rd…", value: true)
                        modeButton(title: "Remove alternate clips", detail: "Remove 1st, keep 2nd, remove 3rd…", value: false)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))

                    Button(action: { Task { await exportVideo() } }) {
                        HStack {
                            if isExporting { ProgressView().tint(.white) }
                            Text(isExporting ? "Processing…" : "Export edited video")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "scissors")
                        }
                        .padding(17)
                        .frame(maxWidth: .infinity)
                        .background(inputURL == nil || isExporting ? Color.gray : Color.blue, in: RoundedRectangle(cornerRadius: 15))
                        .foregroundStyle(.white)
                    }
                    .disabled(inputURL == nil || isExporting)

                    if isExporting || progress > 0 {
                        ProgressView(value: progress)
                            .tint(.cyan)
                    }
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if outputURL != nil {
                        Button {
                            showShare = true
                        } label: {
                            Label("Save or share finished video", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(15)
                                .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Text("Processing happens on your iPhone. Your original video is not modified.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.085))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShare) {
                if let outputURL {
                    ShareSheet(items: [outputURL])
                }
            }
            .alert("AutoCut Studio", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func modeButton(title: String, detail: String, value: Bool) -> some View {
        Button {
            keepFirst = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: keepFirst == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(keepFirst == value ? .cyan : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary).fontWeight(.medium)
                    Text(detail).foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
            }
            .padding(12)
            .background(keepFirst == value ? Color.cyan.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AutoCutError.cannotLoad
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("AutoCut_Input_\(UUID().uuidString).\(ext)")
            try data.write(to: url, options: .atomic)
            inputURL = url
            videoName = url.lastPathComponent
            outputURL = nil
            progress = 0
            status = "Video ready. Choose your cutting settings."
        } catch {
            errorMessage = "Could not load this video: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportVideo() async {
        guard let inputURL else { return }
        isExporting = true
        progress = 0
        outputURL = nil
        status = "Preparing video…"
        defer { isExporting = false }

        do {
            let asset = AVURLAsset(url: inputURL)
            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            guard duration.isFinite, duration > 0 else { throw AutoCutError.invalidDuration }

            let composition = AVMutableComposition()
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
                  let destinationVideo = composition.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { throw AutoCutError.noVideoTrack }

            let sourceVideoDuration = try await sourceVideo.load(.timeRange)
            let videoTransform = try await sourceVideo.load(.preferredTransform)
            destinationVideo.preferredTransform = videoTransform

            let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
            let destinationAudio = sourceAudio == nil ? nil : composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            )

            var cursor = 0.0
            var index = 0
            var insertAt = CMTime.zero
            var keptDuration = 0.0

            while cursor < duration - 0.0001 {
                let end = min(cursor + interval, duration)
                let shouldKeep = keepFirst ? index.isMultiple(of: 2) : !index.isMultiple(of: 2)
                if shouldKeep && end - cursor > 0.02 {
                    let startTime = CMTime(seconds: cursor, preferredTimescale: 600)
                    let endTime = CMTime(seconds: end, preferredTimescale: 600)
                    let range = CMTimeRange(start: startTime, end: endTime)
                    try destinationVideo.insertTimeRange(range, of: sourceVideo, at: insertAt)

                    if let sourceAudio, let destinationAudio {
                        let audioDuration = try await sourceAudio.load(.timeRange)
                        let audioEnd = min(endTime, CMTimeRangeGetEnd(audioDuration))
                        if CMTimeCompare(audioEnd, startTime) > 0 {
                            let audioRange = CMTimeRange(start: startTime, end: audioEnd)
                            try destinationAudio.insertTimeRange(audioRange, of: sourceAudio, at: insertAt)
                        }
                    }
                    insertAt = CMTimeAdd(insertAt, CMTime(seconds: end - cursor, preferredTimescale: 600))
                    keptDuration += end - cursor
                }
                cursor = end
                index += 1
            }

            guard keptDuration > 0 else { throw AutoCutError.noSegments }
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("AutoCut_\(Date.now.timeIntervalSince1970).mp4")
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw AutoCutError.exportUnavailable
            }
            exporter.outputURL = output
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true

            status = "Exporting accurate cuts…"
            let progressTask = Task {
                while !Task.isCancelled {
                    progress = Double(exporter.progress)
                    if exporter.status != .exporting { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            await withCheckedContinuation { continuation in
                exporter.exportAsynchronously {
                    continuation.resume()
                }
            }
            progressTask.cancel()

            guard exporter.status == .completed else {
                throw exporter.error ?? AutoCutError.exportFailed
            }
            progress = 1
            outputURL = output
            status = "Export complete. Your original video is unchanged."
        } catch {
            status = "Export failed."
            errorMessage = error.localizedDescription
        }
    }
}

enum AutoCutError: LocalizedError {
    case cannotLoad, invalidDuration, noVideoTrack, noSegments, exportUnavailable, exportFailed
    var errorDescription: String? {
        switch self {
        case .cannotLoad: return "The selected video could not be read."
        case .invalidDuration: return "The video's duration could not be determined."
        case .noVideoTrack: return "No video track was found in this file."
        case .noSegments: return "No clips remain. Choose the other cutting mode or a shorter interval."
        case .exportUnavailable: return "The video export session could not be created."
        case .exportFailed: return "The export could not be completed."
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
