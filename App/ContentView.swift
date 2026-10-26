import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var runner: RunnerModel

    @State private var showGame = false
    @State private var showConsole = false
    @State private var showSettings = false
    @State private var showImport = false
    @State private var jumpLine: Int?
    @State private var newProjectName = ""
    @State private var newFileName = ""
    @State private var askNewProject = false
    @State private var askNewFile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                fileTabs
                Divider()
                CodeEditor(text: store.text, loadID: store.loadID, jumpLine: $jumpLine) { store.textChanged($0) }
            }
            .navigationTitle(store.current?.name ?? "raylib")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { projectMenu }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showConsole = true } label: {
                        Image(systemName: runner.diagnostics.contains { $0.isError } ? "exclamationmark.octagon.fill" : "terminal")
                            .foregroundStyle(runner.diagnostics.contains { $0.isError } ? .red : .accentColor)
                    }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    Button { run() } label: {
                        Image(systemName: "play.fill").foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.green, in: Capsule())
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            GameScreen(isPresented: $showGame, showConsole: $showConsole)
                .environmentObject(store).environmentObject(runner)
                .sheet(isPresented: $showConsole) { consoleSheet }
        }
        .sheet(isPresented: Binding(get: { showConsole && !showGame }, set: { showConsole = $0 })) { consoleSheet }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store).environmentObject(runner) }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { store.importFiles(urls) }
        }
        .alert("New project", isPresented: $askNewProject) {
            TextField("Name", text: $newProjectName)
            Button("Create") { if let p = store.create(name: newProjectName) { store.open(p) }; newProjectName = "" }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
        .alert("New file", isPresented: $askNewFile) {
            TextField("name.c or name.h", text: $newFileName)
            Button("Create") { store.newFile(newFileName); newFileName = "" }
            Button("Cancel", role: .cancel) { newFileName = "" }
        }
        .onAppear {
            runner.onCompileFailure = { showGame = false; showConsole = true }
        }
    }

    private var consoleSheet: some View {
        ConsoleView { d in
            if let idx = store.files.firstIndex(of: d.file), store.currentFile != store.files[idx] { store.openFile(d.file) }
            showConsole = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { jumpLine = d.line }
        }
        .environmentObject(runner)
        .presentationDetents([.medium, .large])
    }

    private var fileTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.files, id: \.self) { f in
                    Button { store.openFile(f) } label: {
                        Text(f).font(.footnote.monospaced())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(f == store.currentFile ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Button { askNewFile = true } label: { Image(systemName: "plus").padding(6) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
    }

    private var projectMenu: some View {
        Menu {
            Section("Projects") {
                ForEach(store.projects) { p in
                    Button { store.open(p) } label: {
                        Label(p.name, systemImage: p.id == store.current?.id ? "checkmark" : "folder")
                    }
                }
            }
            Button { askNewProject = true } label: { Label("New project…", systemImage: "plus") }
            Button { showImport = true } label: { Label("Import files…", systemImage: "square.and.arrow.down") }
            if store.files.count > 1 {
                Button(role: .destructive) { store.deleteCurrentFile() } label: { Label("Delete \(store.currentFile)", systemImage: "trash") }
            }
            if let p = store.current {
                Button(role: .destructive) { store.delete(p) } label: { Label("Delete project", systemImage: "trash.fill") }
            }
        } label: { Image(systemName: "folder") }
    }

    private func run() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        runner.clear()
        showGame = true
    }
}
