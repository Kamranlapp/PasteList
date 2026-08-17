enum AppConfiguration {
    #if DEBUG
    static let name = "PasteDebug"
    #else
    static let name = "PasteList"
    #endif
    static let bundleIdentifier = "com.kam.pastelist"
    static let isOnboardingEnabled = true
}
