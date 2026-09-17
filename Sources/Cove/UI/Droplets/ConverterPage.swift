import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConverterPage: View {
    @ObservedObject var converter: Converter
    @ObservedObject var coordinator: NotchCoordinator
    let notchTop: CGFloat

    @State private var pending: [URL] = []
    @State private var unsupportedMessage: String?
    @State private var unsupportedMessageTask: Task<Void, Never>?

    private var detectedPresets: [ConvertPreset] {
        var seen: Set<ConvertPreset> = []
        var out: [ConvertPreset] = []
        for url in pending {
            for preset in ConvertPreset.presets(forExtension: url.pathExtension) where !seen.contains(preset) {
                seen.insert(preset)
                out.append(preset)
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            dropZone
            if let unsupportedMessage {
                Text(unsupportedMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange.opacity(0.9))
                    .lineLimit(2)
            }
            if !detectedPresets.isEmpty { presetChips }
            if !jobsEmpty { jobList }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var dropZone: some View {
        Group {
            if jobsEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 26)).foregroundStyle(.white.opacity(0.7))
                    Text(pending.isEmpty ? "Arraste arquivos pra cá" : "\(pending.count) arquivo(s) selecionado(s)")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    chooseButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                    Text(pending.isEmpty ? "Arraste arquivos pra cá" : "\(pending.count) arquivo(s) selecionado(s)")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Spacer(minLength: 4)
                    chooseButton
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(coordinator.dragActive ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(coordinator.dragActive ? 0.4 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
        .onChange(of: coordinator.converterDropRequest) { _, req in
            if let urls = req?.value { accept(urls) }
        }
    }

    private var chooseButton: some View {
        Button("Escolher…") { chooseFiles() }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.12)))
    }

    private func accept(_ urls: [URL]) {
        let (supported, unsupported) = ConvertPreset.partition(urls)
        pending = supported
        showUnsupportedMessageIfNeeded(unsupported)
    }

    private func showUnsupportedMessageIfNeeded(_ unsupported: [URL]) {
        unsupportedMessageTask?.cancel()
        guard !unsupported.isEmpty else {
            unsupportedMessage = nil
            return
        }
        let exts = unsupported.map { $0.pathExtension.isEmpty ? "?" : $0.pathExtension }
        unsupportedMessage = "\(unsupported.count) arquivo(s) sem conversão disponível (\(exts.joined(separator: ", ")))"
        unsupportedMessageTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            unsupportedMessage = nil
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(detectedPresets, id: \.self) { preset in
                    Button(preset.label) {
                        converter.enqueue(pending, preset: preset)
                        pending = []
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
            }
        }
    }

    private var jobsEmpty: Bool { converter.jobs.isEmpty && detectedPresets.isEmpty }

    private var jobList: some View {
        VStack(spacing: 4) {
            if !converter.jobs.isEmpty {
                HStack {
                    Text("Fila").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("Limpar concluídos") { converter.clearCompleted() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(converter.jobs) { job in
                        jobRow(job)
                    }
                }
            }
        }
    }

    private func jobRow(_ job: ConvertJob) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(job.input.lastPathComponent).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                stateLabel(job.state)
            }
            if case .running = job.state {
                ProgressView(value: job.progress).tint(.white.opacity(0.8))
            }
            if case .done(let output) = job.state {
                HStack(spacing: 8) {
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                    Button("Enviar à cesta") { coordinator.shelf.add([output]) }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    @ViewBuilder
    private func stateLabel(_ state: ConvertJob.State) -> some View {
        switch state {
        case .queued: Text("Na fila").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        case .running: Text("Convertendo…").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
        case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green.opacity(0.8))
        case .failed(let message): Text(message).font(.system(size: 9)).foregroundStyle(.red.opacity(0.8)).lineLimit(1)
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        accept(panel.urls)
    }
}
