import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let store = UsageStore()
    private let settings = AppSettings()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupMenuBarObservers()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        if let image = NSImage(named: "MenuBarIcon") {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else if let symbol = NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: nil) {
            button.image = symbol
        } else {
            button.title = "₵"
        }
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsageView(store: store, settings: settings)
        )
        self.popover = popover
    }

    private func setupMenuBarObservers() {
        Publishers.CombineLatest3(
            store.$today,
            settings.$showInMenuBar,
            settings.$menuBarDisplay
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.updateMenuBarTitle()
        }
        .store(in: &cancellables)
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem?.button else { return }
        guard settings.showInMenuBar else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            return
        }
        button.imagePosition = .imageLeft
        let text: String
        let color: NSColor
        switch settings.menuBarDisplay {
        case .cost:
            text = " " + String(format: "$%.2f", store.today.totalCost)
            color = NSColor(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0, alpha: 1)
        case .tokens:
            let total = store.today.inputTokens + store.today.outputTokens
                + store.today.cacheWriteTokens + store.today.cacheReadTokens
            text = " " + formatTokens(total)
            color = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
    }

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
