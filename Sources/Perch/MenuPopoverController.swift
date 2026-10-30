import AppKit
import SwiftUI

@MainActor
final class MenuPopoverController: NSObject {
    private let popover = NSPopover()
    private let statusItem: NSStatusItem
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(store: AppStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // A transient popover would dismiss the input destination when a picker opens.
        popover.behavior = .applicationDefined
        // Status-item toggles should not wait on an asynchronous presentation transition.
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: MenuContent(store: store)
                .onExitCommand { [weak self] in self?.dismiss() }
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.3.layers.3d", accessibilityDescription: "Perch")
            button.image?.isTemplate = true
            button.toolTip = "Perch"
            button.setAccessibilityLabel("Perch")
            button.target = self
            button.action = #selector(togglePopover)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let window = self.popover.contentViewController?.view.window
            if event.window !== window, event.window !== self.statusItem.button?.window {
                self.dismissIfNotEditing()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissIfNotEditing()
        }
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        if popover.isShown { dismiss() }
        else { present() }
    }

    private func present() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func dismiss() {
        // End editing only on dismissal, never when another app takes focus.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
        popover.close()
    }

    private func dismissIfNotEditing() {
        let editor = popover.contentViewController?.view.window?.firstResponder as? NSTextView
        guard popover.isShown, editor?.isFieldEditor != true else { return }
        dismiss()
    }
}
