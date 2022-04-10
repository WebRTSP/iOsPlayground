import SwiftUI

@main
struct iOsPlaygroundApp: App {
    private let controller = Controller()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
    }
}
