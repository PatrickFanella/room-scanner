import SwiftUI

@main
struct RoomScannerApp: App {
    @State private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(store)
        }
    }
}
