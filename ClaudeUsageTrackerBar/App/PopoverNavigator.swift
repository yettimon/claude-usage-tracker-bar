import Foundation

/// Drives which screen the popover shows. Lifted out of `UsageView` so the
/// status-bar right-click menu can jump straight to settings.
@MainActor
final class PopoverNavigator: ObservableObject {
    @Published var showSettings = false
}
