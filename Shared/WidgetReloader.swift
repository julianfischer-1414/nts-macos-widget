import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

protocol WidgetReloading {
    func reloadTimelines()
}

struct WidgetReloader: WidgetReloading {
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "WidgetReloader")

    func reloadTimelines() {
        #if canImport(WidgetKit)
        // Exactly one reload per widget kind. `reloadAllTimelines()` on top
        // causes chronod to dedupe and schedule provider runs LATER, not sooner.
        for kind in AppConstants.allWidgetKinds {
            logger.log("reloadTimelines requested kind=\(kind, privacy: .public)")
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        #endif
    }
}
