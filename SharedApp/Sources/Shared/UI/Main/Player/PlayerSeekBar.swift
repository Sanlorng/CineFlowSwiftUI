import SwiftUI

/// Keeps metadata and preview work separate from the active playback session.
struct PlayerSeekBar: View {
    let source: PlayerSource
    let duration: TimeInterval
    let currentTime: TimeInterval
    @Binding var isScrubbing: Bool
    @Binding var scrubPosition: TimeInterval
    let seek: (TimeInterval) -> Void
    @State private var chapters: [PlayerChapter] = []
    @State private var hoveredTime: TimeInterval?
    @State private var preview: MediaPreviewImage?
    @State private var isLoading = false
    @State private var cache: [Int: MediaPreviewImage] = [:]
    @State private var cacheOrder: [Int] = []

    private var previewTime: TimeInterval? { isScrubbing ? scrubPosition : hoveredTime }
    private var previewBucket: Int? {
        guard let time = previewTime, time.isFinite, duration.isFinite, duration > 0 else { return nil }
        return Int(max(0, min(time, duration - 0.1)) / 5)
    }
    private var displayedTime: TimeInterval { isScrubbing ? scrubPosition : currentTime }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                Slider(value: Binding(get: { min(max(displayedTime, 0), max(duration, 1)) }, set: { scrubPosition = $0 }),
                       in: 0...max(duration, 1), onEditingChanged: { editing in
                    if editing { scrubPosition = currentTime }
                    isScrubbing = editing
                    if !editing { seek(scrubPosition) }
                })
                .tint(.white.opacity(0.92))
                .disabled(duration <= 0)
                .accessibilityLabel("播放进度")
                .overlay {
                    ForEach(chapters.filter { $0.time > 0 && $0.time < duration }) { chapter in
                        Rectangle().fill(.white.opacity(0.7)).frame(width: 2, height: 6)
                            .position(x: x(for: chapter.time, width: geometry.size.width), y: geometry.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hoveredTime = max(0, min(1, (location.x - 8) / max(geometry.size.width - 16, 1))) * duration
                    case .ended: hoveredTime = nil
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let time = previewTime, duration > 0 {
                        previewCard(time: time)
                            .frame(width: 180)
                            .offset(x: max(0, min(geometry.size.width - 180, x(for: time, width: geometry.size.width) - 90)), y: -28)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 22)
            if !chapters.isEmpty {
                HStack {
                    Menu {
                        ForEach(chapters) { chapter in
                            Button { seek(chapter.time) } label: {
                                if chapter.id == PlayerChapter.current(in: chapters, at: displayedTime)?.id {
                                    Label("\(timestamp(chapter.time))  \(chapter.title)", systemImage: "checkmark")
                                } else { Text("\(timestamp(chapter.time))  \(chapter.title)") }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet.rectangle")
                            Text(PlayerChapter.current(in: chapters, at: displayedTime)?.title ?? "章节")
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("选择章节")
                    Spacer()
                    Text("\(chapters.count) 个章节")
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize()
                }
                .font(.caption)
            }
        }
        .task {
            let result = await MediaPreviewProvider.chapters(source: source)
            guard !Task.isCancelled else { return }
            chapters = result
        }
        .task(id: previewBucket) {
            preview = nil
            isLoading = false
            guard let bucket = previewBucket else { return }
            if let cached = cache[bucket] { preview = cached; return }
            isLoading = true
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let result = await MediaPreviewProvider.frame(source: source, time: Double(bucket * 5))
            guard !Task.isCancelled else { return }
            preview = result
            isLoading = false
            if let result {
                cache[bucket] = result
                cacheOrder.append(bucket)
                if cacheOrder.count > 60 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
            }
        }
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        8 + max(0, min(1, time / max(duration, 1))) * max(width - 16, 1)
    }

    private func previewCard(time: TimeInterval) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Color.black
                if let preview {
                    Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
                } else if isLoading { ProgressView().controlSize(.small) }
                else { Text("预览不可用").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(height: 101)
            Text(timestamp(time)).font(.caption.monospacedDigit())
            if let chapter = PlayerChapter.current(in: chapters, at: time) {
                Text(chapter.title).font(.caption2).lineLimit(1)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    private func timestamp(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.isFinite ? time : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
