import WidgetKit
import SwiftUI

@main
struct CentmondWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CentmondWidgets()
        CentmondWidgetsControl()
        BudgetLiveActivity()
    }
}
