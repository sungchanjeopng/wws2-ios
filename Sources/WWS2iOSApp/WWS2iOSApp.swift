import SwiftUI

@main
struct WWS2iOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("WESSWARE")
                .font(.largeTitle).bold()
            Text("iOS port (in progress)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
