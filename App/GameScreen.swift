import SwiftUI

struct RLGLRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RLGLView {
        let v = RLGLView(frame: .zero)
        RLGLView.active = v
        return v
    }
    func updateUIView(_ uiView: RLGLView, context: Context) {}
}

/// Full-screen raylib output. The program is started once the GL view is on screen.
struct GameScreen: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var runner: RunnerModel
    @Binding var isPresented: Bool
    @Binding var showConsole: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RLGLRepresentable().ignoresSafeArea()

            VStack {
                HStack(spacing: 10) {
                    Button {
                        if runner.isRunning { runner.stop() } else { isPresented = false }
                    } label: {
                        Label(runner.isRunning ? "Stop" : "Close", systemImage: runner.isRunning ? "stop.fill" : "xmark")
                            .font(.footnote.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Button { showConsole = true } label: {
                        Image(systemName: "terminal")
                            .padding(8).background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    if !runner.isRunning, let code = runner.exitCode {
                        Text("exit \(code)").font(.caption.monospaced())
                            .padding(6).background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, 12).padding(.top, 6)
                .tint(.white)
                Spacer()
            }
        }
        .onAppear {
            // wait one runloop turn so the GL view is laid out before raylib asks for its size
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let p = store.current { runner.run(project: p, headers: store.headersDir) }
            }
        }
        .onChange(of: runner.isRunning) { running in
            // the program ended by itself without errors -> return to the editor
            if !running, runner.exitCode == 0 { isPresented = false }
        }
        .statusBarHidden(true)
    }
}
