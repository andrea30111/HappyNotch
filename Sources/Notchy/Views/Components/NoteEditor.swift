import AppKit
import SwiftUI

/// Plain-text editor backed by NSTextView so ⌘↩ can act on the line under the caret.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var onConvertLine: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor.black.withAlphaComponent(0.82)
        textView.insertionPointColor = .black
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black.withAlphaComponent(0.82)]
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setAccessibilityLabel("Notepad. Press Command Return to turn the current line into a task.")

        context.coordinator.textView = textView
        context.coordinator.installKeyMonitor()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NSTextView?
        private var monitor: Any?

        init(_ parent: NoteEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }

        func installKeyMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let textView = self.textView,
                      textView.window?.firstResponder === textView,
                      event.keyCode == 36 || event.keyCode == 76,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                else { return event }
                self.convertCurrentLine(in: textView)
                return nil
            }
        }

        func removeKeyMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func convertCurrentLine(in textView: NSTextView) {
            let string = textView.string as NSString
            guard string.length > 0 else { return }
            let caret = min(textView.selectedRange().location, max(0, string.length - 1))
            let lineRange = string.lineRange(for: NSRange(location: caret, length: 0))
            var line = string.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["- [ ] ", "[ ] ", "- ", "* ", "• "] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count))
                break
            }
            guard !line.isEmpty else { return }
            if textView.shouldChangeText(in: lineRange, replacementString: "") {
                textView.replaceCharacters(in: lineRange, with: "")
                textView.didChangeText()
            }
            parent.onConvertLine(line)
        }
    }
}
