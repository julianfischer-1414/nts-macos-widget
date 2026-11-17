import Foundation

enum AppConstants {
    static let sharedPlayerStateKey = "sharedPlayerState"

    /// URL scheme the widget's controls open the host app with. Must match
    /// `CFBundleURLTypes` in NTSWidgetHost/Info.plist. See `WidgetAction` for
    /// why the controls are links rather than App Intents.
    static let urlScheme = "ntsradio"
    static let widgetKind = "NTSWidget"
    static let ntsLiveAPIURL = URL(string: "https://www.nts.live/api/v2/live")!
    /// Opened by the host when the widget's header is tapped, so the user can
    /// check track IDs on the site (see `WidgetAction.openWebsite`).
    static let ntsWebsiteURL = URL(string: "https://www.nts.live")!

    /// The widget extension's bundle identifier, which also names its sandbox
    /// container — the directory the host and the extension share state through.
    /// Must match `PRODUCT_BUNDLE_IDENTIFIER` of the NTSWidgetExtension target.
    static let widgetExtensionBundleIdentifier = "com.fede.NTSWidgetHost.NTSWidgetExtension"
}
