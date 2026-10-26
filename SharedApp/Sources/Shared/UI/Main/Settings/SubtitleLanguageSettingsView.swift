import SwiftUI

struct SubtitleLanguageSettingsView: View {
    @AppStorage(SubtitleLanguagePreferences.storageKey) private var storedQueue = "[]"
    @State private var newEntry = ""
    @State private var queueInput = ""
    @State private var inputError: String?

    private var queue: [String] { SubtitleLanguagePreferences.decode(storedQueue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("字幕语言优先级").font(.headline)
            Text("按从上到下的顺序匹配内嵌字幕语言，未命中时使用原来的选择规则。手动选择的新语言会追加到末尾，已有语言保持原位置。没有语言标签时使用字幕名称。")
                .font(.callout).foregroundStyle(.secondary)
            GroupBox {
                VStack(spacing: 10) {
                    if queue.isEmpty {
                        Text("尚无偏好，使用默认字幕选择规则。")
                            .foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(Array(queue.enumerated()), id: \.element) { index, entry in
                        HStack {
                            Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 24)
                            Text(entry).textSelection(.enabled)
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).help("提高优先级").accessibilityLabel("提高 \(entry) 的优先级")
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == queue.count - 1).help("降低优先级").accessibilityLabel("降低 \(entry) 的优先级")
                            Button(role: .destructive) { save(queue.filter { $0 != entry }) } label: { Image(systemName: "minus.circle") }
                                .help("删除").accessibilityLabel("删除 \(entry)")
                        }
                    }
                    Divider()
                    HStack {
                        TextField("语言或字幕名称，例如 zh-cn", text: $newEntry)
                            .onSubmit(addEntry)
                        Button("添加", action: addEntry)
                            .disabled(SubtitleLanguagePreferences.normalized(newEntry).isEmpty)
                    }
                }.padding(8)
            }
            GroupBox("完整队列") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("[zh, zh-cn, ja]", text: $queueInput, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...6)
                    Text("支持 [zh, zh-cn] 或 [\"zh\", \"zh-cn\"]。应用会替换整个队列；[] 可清空。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("应用队列") {
                            do { save(try SubtitleLanguagePreferences.parse(queueInput)) }
                            catch { inputError = error.localizedDescription }
                        }
                        Button("载入当前队列") { queueInput = storedQueue; inputError = nil }
                    }
                    if let inputError { Text(inputError).foregroundStyle(.red).font(.caption) }
                }.padding(8)
            }
            Text("偏好会保存并用于后续打开的视频，不会切换当前正在使用的字幕。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { queueInput = storedQueue }
    }

    private func save(_ values: [String]) {
        storedQueue = SubtitleLanguagePreferences.encode(values)
        queueInput = storedQueue
        inputError = nil
    }

    private func addEntry() {
        guard !SubtitleLanguagePreferences.normalized(newEntry).isEmpty else { return }
        save(queue + [newEntry])
        newEntry = ""
    }

    private func move(_ index: Int, by offset: Int) {
        var values = queue
        guard values.indices.contains(index), values.indices.contains(index + offset) else { return }
        values.swapAt(index, index + offset)
        save(values)
    }
}
