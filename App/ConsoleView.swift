import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var runner: RunnerModel
    var onJump: (Diagnostic) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !runner.diagnostics.isEmpty {
                    List(runner.diagnostics) { d in
                        Button { onJump(d) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: d.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(d.isError ? .red : .yellow)
                                    Text(d.line > 0 ? "\(d.file):\(d.line)" : "build").font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Text(d.message).font(.footnote.monospaced()).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 220)
                    Divider()
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(runner.lines) { l in
                                Text(l.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(color(l.kind))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(l.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: runner.lines.count) { _ in
                        if let last = runner.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Text(runner.status).font(.caption).foregroundStyle(.secondary) }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Clear") { runner.clear() } }
            }
        }
    }

    private func color(_ kind: Int) -> Color {
        switch kind { case 2: return .red; case 3: return .secondary; default: return .primary }
    }
}
