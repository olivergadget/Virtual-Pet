import SwiftUI
import WidgetKit

@main
struct PetWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PetStatusWidget()
        // Lock Screen accessories are an iPhone and iPad affair.
        #if os(iOS)
        PetLockScreenWidget()
        #endif
    }
}
