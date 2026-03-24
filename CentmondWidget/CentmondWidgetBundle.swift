//
//  CentmondWidgetBundle.swift
//  CentmondWidget
//
//  Created by Mani on 16.03.26.
//

import WidgetKit
import SwiftUI

@main
struct CentmondWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodaySpendingWidget()
        BudgetWidget()
        UpcomingBillsWidget()
        SafeToSpendWidget()
        NetWorthWidget()
    }
}
