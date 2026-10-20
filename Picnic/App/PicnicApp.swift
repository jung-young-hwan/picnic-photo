import SwiftUI

@main
struct PicnicApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .fontDesign(.rounded)
        }
    }
}
