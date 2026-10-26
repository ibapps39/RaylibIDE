import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var runner: RunnerModel
    @Environment(\.dismiss) private var dismiss

    @State private var ref = "5.5"
    @State private var busy = false
    @State private var message = ""
    @State private var importHeaders = false

    var body: some View {
        NavigationStack {
            Form {
                Section("JIT") {
                    HStack {
                        Image(systemName: runner.jitAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(runner.jitAvailable ? .green : .red)
                        Text(runner.jitAvailable ? "JIT is enabled — programs can run" : "JIT is NOT enabled — programs can't run yet")
                    }
                    Button("Re-check") { runner.refreshJIT() }
                    Text("This app compiles your C code to machine code on the device, which iOS only allows when JIT is enabled for the app. Options: launch it with a JIT enabler (e.g. StikJIT / AltStore's “Enable JIT”), install it with TrollStore, or run it from Xcode. Without JIT, compile and edit still work, but running does not.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("raylib headers (autocomplete + #include)") {
                    Text("Using: \(CompletionEngine.shared.headerInfo)").font(.footnote)
                    TextField("GitHub tag or branch", text: $ref)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await download() }
                    } label: { HStack { Text("Download headers from GitHub"); if busy { Spacer(); ProgressView() } } }
                    .disabled(busy)
                    Button("Import headers from Files…") { importHeaders = true }
                    Button("Revert to bundled headers", role: .destructive) {
                        try? FileManager.default.removeItem(at: store.headersDir)
                        try? FileManager.default.createDirectory(at: store.headersDir, withIntermediateDirectories: true)
                        CompletionEngine.shared.reload(overrideDir: store.headersDir)
                        message = "Reverted."
                    }
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    Text("The raylib *library* is compiled into the app at build time (scripts/fetch_deps.sh pulls it from GitHub, or uses a copy you put in Vendor/raylib). Headers fetched here must match that version, otherwise calls to functions missing from the built-in library fail to link.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Files") {
                    Text("Projects live in the Files app under On My iPhone → RaylibIDE → Projects. Drop .c/.h files, textures, sounds and shaders there (or use Import in the project menu). Your program's working directory is its project folder, so LoadTexture(\"player.png\") just works.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importHeaders, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for u in urls {
                    let ok = u.startAccessingSecurityScopedResource()
                    defer { if ok { u.stopAccessingSecurityScopedResource() } }
                    let dest = store.headersDir.appendingPathComponent(u.lastPathComponent)
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.copyItem(at: u, to: dest)
                }
                CompletionEngine.shared.reload(overrideDir: store.headersDir)
                message = "Imported \(urls.count) file(s)."
            }
        }
    }

    private func download() async {
        busy = true; defer { busy = false }
        let base = "https://raw.githubusercontent.com/raysan5/raylib/\(ref.trimmingCharacters(in: .whitespaces))/src/"
        var ok = 0
        for name in ["raylib.h", "raymath.h", "rlgl.h"] {
            guard let url = URL(string: base + name) else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { message = "\(name): not found for “\(ref)”"; return }
                try data.write(to: store.headersDir.appendingPathComponent(name))
                ok += 1
            } catch { message = "\(name): \(error.localizedDescription)"; return }
        }
        CompletionEngine.shared.reload(overrideDir: store.headersDir)
        message = "Downloaded \(ok) headers (\(ref))."
    }
}
