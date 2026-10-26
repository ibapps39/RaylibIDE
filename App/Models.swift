import Foundation
import SwiftUI
import UIKit

// MARK: - Console / runner

struct ConsoleLine: Identifiable {
    let id = UUID()
    let kind: Int          // 0 stdout, 2 compiler diagnostic, 3 status
    let text: String
}

struct Diagnostic: Identifiable, Hashable {
    let id = UUID()
    let file: String
    let line: Int
    let message: String
    let isError: Bool
}

private let logCallback: rlrun_log_fn = { kind, text, ctx in
    guard let ctx = ctx, let text = text else { return }
    let s = String(cString: text)
    let k = Int(kind)
    let model = Unmanaged<RunnerModel>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { model.handleLog(kind: k, text: s) }
}

private let doneCallback: rlrun_done_fn = { code, ctx in
    guard let ctx = ctx else { return }
    let model = Unmanaged<RunnerModel>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { model.handleDone(code: code) }
}

final class RunnerModel: ObservableObject {
    @Published var lines: [ConsoleLine] = []
    @Published var diagnostics: [Diagnostic] = []
    @Published var status = "Ready"
    @Published var isRunning = false
    @Published var exitCode: Int32? = nil
    @Published var jitAvailable = false

    var onCompileFailure: (() -> Void)?
    private var hadError = false

    private var ctx: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    func start() {
        refreshJIT()
        rlrun_capture_stdio(logCallback, ctx)
    }

    func refreshJIT() { jitAvailable = rlrun_jit_available() != 0 }

    func clear() { lines.removeAll(); diagnostics.removeAll() }

    // Parses "file.c:12: error: message" (tcc format)
    private static let diagRegex = try! NSRegularExpression(pattern: #"^(.*?):(\d+):\s*(error|warning):\s*(.*)$"#)

    func handleLog(kind: Int, text: String) {
        switch kind {
        case 2:
            let range = NSRange(text.startIndex..., in: text)
            if let m = Self.diagRegex.firstMatch(in: text, range: range),
               let f = Range(m.range(at: 1), in: text), let l = Range(m.range(at: 2), in: text),
               let t = Range(m.range(at: 3), in: text), let msg = Range(m.range(at: 4), in: text) {
                let isErr = text[t] == "error"
                if isErr { hadError = true }
                diagnostics.append(Diagnostic(file: (String(text[f]) as NSString).lastPathComponent,
                                              line: Int(text[l]) ?? 0, message: String(text[msg]), isError: isErr))
            } else {
                hadError = true
                diagnostics.append(Diagnostic(file: "", line: 0, message: text.replacingOccurrences(of: "tcc: ", with: ""), isError: true))
            }
            lines.append(ConsoleLine(kind: 2, text: text))
        case 3:
            status = text
            lines.append(ConsoleLine(kind: 3, text: "— \(text) —"))
        default:
            for part in text.split(separator: "\n", omittingEmptySubsequences: true) {
                lines.append(ConsoleLine(kind: 0, text: String(part)))
            }
            if lines.count > 3000 { lines.removeFirst(lines.count - 3000) }
        }
    }

    func handleDone(code: Int32) {
        isRunning = false
        exitCode = code
        UIApplication.shared.isIdleTimerDisabled = false
        status = hadError ? "Failed" : "Finished (exit \(code))"
        if hadError && code < 0 { onCompileFailure?() }
    }

    func run(project: Project, headers: URL) {
        guard !isRunning else { return }
        refreshJIT()
        diagnostics.removeAll()
        hadError = false
        exitCode = nil
        lines.append(ConsoleLine(kind: 3, text: "━━ Run \(project.name) ━━"))

        let files = project.sourceFiles().map { $0.path }
        if files.isEmpty {
            handleLog(kind: 2, text: "error: project has no .c files")
            handleDone(code: -1); return
        }
        if !jitAvailable {
            handleLog(kind: 2, text: "error: JIT is not enabled for this app, so C code can't be executed. Open Settings → JIT for how to enable it.")
            handleDone(code: -1); return
        }

        let include = (Bundle.main.resourcePath ?? "") + "/include"
        isRunning = true
        status = "Starting"
        UIApplication.shared.isIdleTimerDisabled = true

        let cfiles = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: files.count)
        for (i, f) in files.enumerated() { cfiles[i] = UnsafePointer(strdup(f)) }
        defer {
            for i in 0..<files.count { free(UnsafeMutableRawPointer(mutating: cfiles[i])) }
            cfiles.deallocate()
        }

        let started: Int32 = project.url.path.withCString { pd in
            include.withCString { inc in
                headers.path.withCString { ov in
                    var cfg = rlrun_config()
                    cfg.project_dir = pd
                    cfg.include_dir = inc
                    cfg.override_dir = ov
                    cfg.files = cfiles
                    cfg.nfiles = Int32(files.count)
                    cfg.log = logCallback
                    cfg.done = doneCallback
                    cfg.ctx = ctx
                    return rlrun_start(&cfg)
                }
            }
        }
        if started != 0 {
            isRunning = false
            handleLog(kind: 2, text: "error: could not start (code \(started))")
        }
    }

    func stop() {
        rlrun_request_stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.isRunning == true { rlrun_force_stop() }
        }
    }
}

// MARK: - Projects

struct Project: Identifiable, Hashable {
    var id: String { url.lastPathComponent }
    let url: URL
    var name: String { url.lastPathComponent }

    func allFiles() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return items.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ["c", "h", "txt", "fs", "vs", "glsl", "md"].contains(ext)
        }.sorted { a, b in
            if a == "main.c" { return true }
            if b == "main.c" { return false }
            return a < b
        }
    }

    func sourceFiles() -> [URL] {
        allFiles().filter { $0.hasSuffix(".c") }.map { url.appendingPathComponent($0) }
    }
}

let sampleMain = """
#include "raylib.h"

int main(void)
{
    InitWindow(800, 450, "raylib on iOS");
    SetTargetFPS(60);

    Vector2 ball = { 400, 225 };
    Vector2 speed = { 4.0f, 3.0f };

    while (!WindowShouldClose())
    {
        ball.x += speed.x;
        ball.y += speed.y;
        if (ball.x < 20 || ball.x > GetScreenWidth() - 20)  speed.x *= -1;
        if (ball.y < 20 || ball.y > GetScreenHeight() - 20) speed.y *= -1;

        if (IsMouseButtonDown(MOUSE_BUTTON_LEFT)) ball = GetMousePosition();   // touch = mouse

        BeginDrawing();
            ClearBackground(RAYWHITE);
            DrawCircleV(ball, 20, MAROON);
            DrawText(TextFormat("FPS: %d - touch to move the ball", GetFPS()), 10, 10, 20, DARKGRAY);
        EndDrawing();
    }

    CloseWindow();
    return 0;
}

"""

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var current: Project?
    @Published var files: [String] = []
    @Published var currentFile = "main.c"
    @Published var text = ""
    @Published var loadID = UUID()          // changes when a different file is loaded

    let root: URL
    let headersDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Projects", isDirectory: true)
        headersDir = docs.appendingPathComponent("Headers", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: headersDir, withIntermediateDirectories: true)
        reload()
        if projects.isEmpty { _ = create(name: "Hello raylib") }
        open(projects[0])
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        projects = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { Project(url: $0) }.sorted { $0.name < $1.name }
    }

    @discardableResult
    func create(name: String) -> Project? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty else { return nil }
        let dir = root.appendingPathComponent(clean, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let main = dir.appendingPathComponent("main.c")
        if !FileManager.default.fileExists(atPath: main.path) { try? sampleMain.write(to: main, atomically: true, encoding: .utf8) }
        reload()
        return projects.first { $0.name == clean }
    }

    func open(_ p: Project) {
        current = p
        files = p.allFiles()
        openFile(files.first ?? "main.c")
    }

    func openFile(_ name: String) {
        guard let p = current else { return }
        currentFile = name
        text = (try? String(contentsOf: p.url.appendingPathComponent(name), encoding: .utf8)) ?? ""
        loadID = UUID()
    }

    func textChanged(_ new: String) {
        text = new
        guard let p = current else { return }
        try? new.write(to: p.url.appendingPathComponent(currentFile), atomically: true, encoding: .utf8)
    }

    func newFile(_ name: String) {
        guard let p = current else { return }
        var n = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        if n.isEmpty { return }
        if (n as NSString).pathExtension.isEmpty { n += ".c" }
        let u = p.url.appendingPathComponent(n)
        if !FileManager.default.fileExists(atPath: u.path) { try? "".write(to: u, atomically: true, encoding: .utf8) }
        files = p.allFiles()
        openFile(n)
    }

    func deleteCurrentFile() {
        guard let p = current, files.count > 1 else { return }
        try? FileManager.default.removeItem(at: p.url.appendingPathComponent(currentFile))
        files = p.allFiles()
        openFile(files.first ?? "main.c")
    }

    func delete(_ p: Project) {
        try? FileManager.default.removeItem(at: p.url)
        reload()
        if projects.isEmpty { _ = create(name: "Hello raylib") }
        if current?.id == p.id { open(projects[0]) }
    }

    /// Copy files picked from the Files app into the project (sources, headers, textures, sounds...).
    func importFiles(_ urls: [URL]) {
        guard let p = current else { return }
        for u in urls {
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let dest = p.url.appendingPathComponent(u.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: u, to: dest)
        }
        files = p.allFiles()
    }
}
