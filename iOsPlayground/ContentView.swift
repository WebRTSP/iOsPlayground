import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: Controller

    var body: some View {
        WebRTCView(controller: controller)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let controller = Controller()
        ContentView(controller: controller)
    }
}
