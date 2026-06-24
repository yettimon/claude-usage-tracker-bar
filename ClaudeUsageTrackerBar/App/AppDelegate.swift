import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var onboardingWindow: NSWindow?
    private let settings = AppSettings()
    private lazy var store = UsageStore(settings: settings)
    private lazy var quotaStore = QuotaStore()
    private lazy var statusStore = ClaudeStatusStore(fetchOnInit: false)
    private lazy var accountStore = AccountStore()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupMenuBarObservers()
        setupWakeObserver()
        showOnboardingIfNeeded()
    }

    func showOnboarding() {
        if let win = onboardingWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            window.orderOut(nil)
        })
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showOnboarding()
        }
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
        let hosting = NSHostingController(
            rootView: UsageView(store: store, quotaStore: quotaStore, statusStore: statusStore, accountStore: accountStore, settings: settings)
        )
        // Track SwiftUI's ideal size so the popover resizes as async sections
        // (status, quota) load in — without this the frame is fixed at show-time
        // and late-arriving content overflows, clipping the top and bottom.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover
    }

    private func setupWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.settings.showQuota else { return }
                await self.retryQuotaFetchAfterWake()
            }
        }
    }

    private func retryQuotaFetchAfterWake() async {
        let delays: [Duration] = [.seconds(3), .seconds(6), .seconds(12)]
        for delay in delays {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await quotaStore.fetch()
            // Stop on success, auth error, or rate limit — only retry for network errors
            if quotaStore.error == nil || quotaStore.error == .notSignedIn || quotaStore.error == .rateLimited { return }
        }
    }

    private func setupMenuBarObservers() {
        Publishers.CombineLatest(
            Publishers.CombineLatest3(store.$today, settings.$showInMenuBar, settings.$menuBarDisplay),
            Publishers.CombineLatest(settings.$menuBarCustomColor, settings.$menuBarColorHex)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.updateMenuBarTitle()
        }
        .store(in: &cancellables)

        settings.$showQuota
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.quotaStore.setEnabled(enabled)
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
        switch settings.menuBarDisplay {
        case .cost:
            text = " " + String(format: "$%.2f", store.today.totalCost)
        case .tokens:
            let total = store.today.inputTokens + store.today.outputTokens
                + store.today.cacheWriteTokens + store.today.cacheReadTokens
            text = " " + formatTokens(total)
        }
        let color: NSColor = settings.menuBarCustomColor
            ? NSColor(Color(hex: settings.menuBarColorHex))
            : .labelColor
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
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
            accountStore.refresh()
            if settings.showQuota { quotaStore.refreshIfStale() }
            statusStore.refreshIfStale()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
