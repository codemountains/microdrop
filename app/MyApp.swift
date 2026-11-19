import SwiftUI

@main struct MyApp: App {
    #if os(iOS)
    @State private var settings = ConnectionSettings()
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            ContentView(settings: settings)
            #else
            ContentView()
            #endif
        }
    }
}
