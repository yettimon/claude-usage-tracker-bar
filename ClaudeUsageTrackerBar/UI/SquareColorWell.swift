import SwiftUI
import AppKit

struct SquareColorWell: NSViewRepresentable {
    @Binding var color: Color

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = NSColor(color)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.wantsLayer = true
        well.layer?.cornerRadius = 3
        well.layer?.masksToBounds = true
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = NSColor(color)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SquareColorWell
        init(_ parent: SquareColorWell) { self.parent = parent }

        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = Color(sender.color)
        }
    }
}
