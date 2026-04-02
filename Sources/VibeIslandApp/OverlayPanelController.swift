import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController {
    private var panel: IslandPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func availableDisplayOptions() -> [OverlayDisplayOption] {
        OverlayDisplayResolver.availableDisplayOptions()
    }

    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        let diagnostics = position(panel: panel, preferredScreenID: preferredScreenID)
        panel.orderFrontRegardless()
        return diagnostics
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func reposition(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        guard let panel else {
            return placementDiagnostics(preferredScreenID: preferredScreenID)
        }

        return position(panel: panel, preferredScreenID: preferredScreenID)
    }

    func placementDiagnostics(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panelSize = panel?.frame.size ?? OverlayDisplayResolver.defaultPanelSize
        return OverlayDisplayResolver.diagnostics(preferredScreenID: preferredScreenID, panelSize: panelSize)
    }

    private func makePanel(model: AppModel) -> IslandPanel {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: OverlayDisplayResolver.defaultPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = NSHostingController(rootView: IslandPanelView(model: model))
        return panel
    }

    private func position(panel: NSPanel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        guard let diagnostics = OverlayDisplayResolver.diagnostics(
            preferredScreenID: preferredScreenID,
            panelSize: panel.frame.size
        ) else {
            return nil
        }

        panel.setFrame(diagnostics.overlayFrame, display: true)
        return diagnostics
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
