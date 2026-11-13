import SwiftUI

@main
struct MacTubeConverterApp: App {
    @StateObject private var model: AppModel

    init() {
        Settings.migrateLegacyDefaults()
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 860)
    }
}
