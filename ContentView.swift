import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import CoreTransferable
import UniformTypeIdentifiers

// Copies the selected movie as a file instead of loading the entire video into RAM.
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
    @State private var duration = 0.0
    @State private var resolution = ""
    @State private var frameRate = ""
    @State private var interval = 2.0
    @State private var keepFirst = true
    @State private var exporting = false
    @State private var progress = 0.0
    @State private var status = "Choose a video to start."
    @State private var outputURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
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
                    if duration > 0 { timelineCard }
                    intervalCard
                    patternCard
                    exportCard
                    Label("Your video is processed on this iPhone. The source file is never modified.",
                          systemImage: "lock.shield")
                        .font(.caption2)
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
                Task { await loadVideo(item) }
            }
            .sheet(isPresented: $showShare) {
                if let outputURL {
                    ShareSheet(items: [outputURL])
                        .presentationDetents([.medium, .large])
                }
            }
            .alert("AutoCut Studio", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    showError = false
