import SwiftUI

@main
struct RaylibIDEApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var runner = RunnerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(runner)
                .onAppear {
                    runner.start()
                    CompletionEngine.shared.reload(overrideDir: store.headersDir)
                }
        }
    }
}
