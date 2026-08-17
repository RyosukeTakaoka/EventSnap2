//
//  EventSnapWidgetBundle.swift
//  EventSnapWidget
//
//  Widget Extensionのエントリーポイント。ホーム画面Widgetと
//  Live ActivityのUIを同じExtensionにまとめる(現在のAppleの推奨構成)。
//

import WidgetKit
import SwiftUI

@main
struct EventSnapWidgetBundle: WidgetBundle {
    var body: some Widget {
        EventSnapWidget()
        EventActivityWidget()
    }
}
