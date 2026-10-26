import SwiftUI
import UIKit

/// UITextView-based C editor: syntax highlighting, auto-indent, completion/symbol bar above the keyboard,
/// and live signature help.
struct CodeEditor: UIViewRepresentable {
    let text: String
    let loadID: UUID
    @Binding var jumpLine: Int?
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = Coordinator.font
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        tv.backgroundColor = .systemBackground
        tv.inputAccessoryView = context.coordinator.bar
        context.coordinator.textView = tv
        tv.text = text
        context.coordinator.highlight()
        context.coordinator.lastLoadID = loadID
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastLoadID != loadID {
            context.coordinator.lastLoadID = loadID
            tv.text = text
            context.coordinator.highlight()
        }
        if let line = jumpLine {
            context.coordinator.jump(to: line)
            DispatchQueue.main.async { self.jumpLine = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        static let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        var parent: CodeEditor
        weak var textView: UITextView?
        var lastLoadID: UUID?
        let bar = CompletionBar()
        private var current: [CompletionItem] = []
        private var highlightWork: DispatchWorkItem?

        init(_ p: CodeEditor) {
            parent = p
            super.init()
            bar.onPick = { [weak self] item in self?.apply(item) }
            bar.onSymbol = { [weak self] s in self?.insertSymbol(s) }
            bar.onDismiss = { [weak self] in self?.textView?.resignFirstResponder() }
            bar.showSymbols()
        }

        // --- highlighting
        private static let numberRe = try! NSRegularExpression(pattern: #"\b(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?[fFuUlL]*)\b"#)
        private static let keywordRe = try! NSRegularExpression(pattern: #"\b(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|true|false|NULL)\b"#)
        private static let preprocRe = try! NSRegularExpression(pattern: #"^\s*#\s*\w+"#, options: [.anchorsMatchLines])
        private static let stringRe = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#)
        private static let lineCommentRe = try! NSRegularExpression(pattern: #"//[^\n]*"#)
        private static let blockCommentRe = try! NSRegularExpression(pattern: #"/\*[\s\S]*?(?:\*/|$)"#)

        func scheduleHighlight() {
            highlightWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.highlight() }
            highlightWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
        }

        func highlight() {
            guard let tv = textView, tv.markedTextRange == nil else { return }
            let ts = tv.textStorage
            let full = NSRange(location: 0, length: ts.length)
            let str = ts.string
            ts.beginEditing()
            ts.setAttributes([.font: Self.font, .foregroundColor: UIColor.label], range: full)
            func paint(_ re: NSRegularExpression?, _ color: UIColor) {
                re?.enumerateMatches(in: str, range: full) { m, _, _ in
                    if let r = m?.range { ts.addAttribute(.foregroundColor, value: color, range: r) }
                }
            }
            let e = CompletionEngine.shared
            paint(Self.numberRe, .systemOrange)
            paint(e.constantRegex, .systemPurple)
            paint(Self.keywordRe, .systemPink)
            paint(e.typeRegex, .systemTeal)
            paint(e.functionRegex, .systemBlue)
            paint(Self.preprocRe, .systemBrown)
            paint(Self.stringRe, .systemRed)
            paint(Self.lineCommentRe, .systemGreen)
            paint(Self.blockCommentRe, .systemGreen)
            ts.endEditing()
            tv.typingAttributes = [.font: Self.font, .foregroundColor: UIColor.label]
        }

        // --- delegate
        func textViewDidChange(_ tv: UITextView) {
            parent.onChange(tv.text)
            scheduleHighlight()
            refreshBar()
        }

        func textViewDidChangeSelection(_ tv: UITextView) { refreshBar() }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
            // auto-indent
            if t == "\n" {
                let ns = tv.text as NSString
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let line = ns.substring(with: lineRange)
                var indent = String(line.prefix { $0 == " " || $0 == "\t" })
                let beforeCaret = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
                let trimmed = beforeCaret.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix("{") { indent += "    " }
                tv.textStorage.replaceCharacters(in: range, with: "\n" + indent)
                tv.selectedRange = NSRange(location: range.location + 1 + indent.count, length: 0)
                textViewDidChange(tv)
                return false
            }
            // dedent when typing a closing brace on an otherwise blank line
            if t == "}" {
                let ns = tv.text as NSString
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let before = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
                if !before.isEmpty, before.allSatisfy({ $0 == " " }) , before.count >= 4 {
                    let r = NSRange(location: range.location - 4, length: 4 + range.length)
                    tv.textStorage.replaceCharacters(in: r, with: "}")
                    tv.selectedRange = NSRange(location: r.location + 1, length: 0)
                    textViewDidChange(tv)
                    return false
                }
            }
            return true
        }

        // --- completion bar
        private func prefixAtCaret() -> (String, NSRange)? {
            guard let tv = textView else { return nil }
            let sel = tv.selectedRange
            guard sel.length == 0 else { return nil }
            let u = Array(tv.text.utf16)
            var i = sel.location
            while i > 0, CompletionEngine.isIdent(u[i - 1]) { i -= 1 }
            if i == sel.location { return nil }
            let r = NSRange(location: i, length: sel.location - i)
            return ((tv.text as NSString).substring(with: r), r)
        }

        func refreshBar() {
            guard let tv = textView else { return }
            bar.setHint(CompletionEngine.shared.signatureHelp(text: tv.text, caret: tv.selectedRange.location))
            if let (prefix, _) = prefixAtCaret(), prefix.first?.isNumber == false {
                current = CompletionEngine.shared.completions(prefix: prefix, document: tv.text)
                if current.isEmpty { bar.showSymbols() } else { bar.show(current) }
            } else { bar.showSymbols() }
        }

        private func apply(_ item: CompletionItem) {
            guard let tv = textView, let (_, r) = prefixAtCaret() else { return }
            var ins = item.insert
            var caretBack = 0
            if item.kind == .function {
                ins += "()"
                caretBack = item.hasParams ? 1 : 0
            }
            tv.textStorage.replaceCharacters(in: r, with: ins)
            tv.selectedRange = NSRange(location: r.location + (ins as NSString).length - caretBack, length: 0)
            textViewDidChange(tv)
        }

        private func insertSymbol(_ s: String) {
            guard let tv = textView else { return }
            let r = tv.selectedRange
            var ins = s
            var back = 0
            switch s {
            case "{": ins = "{}"; back = 1
            case "(": ins = "()"; back = 1
            case "[": ins = "[]"; back = 1
            case "\"": ins = "\"\""; back = 1
            case "⇥": ins = "    "
            default: break
            }
            tv.textStorage.replaceCharacters(in: r, with: ins)
            tv.selectedRange = NSRange(location: r.location + (ins as NSString).length - back, length: 0)
            textViewDidChange(tv)
        }

        func jump(to line: Int) {
            guard let tv = textView, line > 0 else { return }
            let ns = tv.text as NSString
            var idx = 0, cur = 1
            while cur < line && idx < ns.length {
                idx = NSMaxRange(ns.lineRange(for: NSRange(location: idx, length: 0)))
                cur += 1
            }
            let r = ns.lineRange(for: NSRange(location: min(idx, max(ns.length - 1, 0)), length: 0))
            tv.becomeFirstResponder()
            tv.selectedRange = NSRange(location: r.location, length: 0)
            tv.scrollRangeToVisible(r)
        }
    }
}

// MARK: - Bar above the keyboard

final class CompletionBar: UIView {
    var onPick: ((CompletionItem) -> Void)?
    var onSymbol: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private let hint = UILabel()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var pickItems: [CompletionItem] = []

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 62))
        autoresizingMask = .flexibleWidth
        backgroundColor = .secondarySystemBackground

        hint.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        hint.textColor = .secondaryLabel
        hint.lineBreakMode = .byTruncatingMiddle
        hint.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint); addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hint.heightAnchor.constraint(equalToConstant: 14),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setHint(_ s: String?) { hint.text = s ?? " " }

    private func button(_ title: String, mono: Bool = true, tint: UIColor = .label) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.baseBackgroundColor = .systemBackground
        cfg.baseForegroundColor = tint
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        cfg.cornerStyle = .medium
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { c in
            var c = c; c.font = mono ? UIFont.monospacedSystemFont(ofSize: 15, weight: .medium) : .systemFont(ofSize: 15); return c
        }
        return UIButton(configuration: cfg)
    }

    private func clear() { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }

    func show(_ items: [CompletionItem]) {
        clear()
        pickItems = items
        for (i, it) in items.enumerated() {
            let tint: UIColor = {
                switch it.kind {
                case .function: return .systemBlue
                case .type: return .systemTeal
                case .constant: return .systemPurple
                case .keyword: return .systemPink
                default: return .label
                }
            }()
            let b = button(it.name, tint: tint)
            b.tag = i
            b.addTarget(self, action: #selector(pick(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
        scroll.setContentOffset(.zero, animated: false)
    }

    func showSymbols() {
        clear()
        for s in ["⇥", "{", "}", "(", ")", "[", "]", ";", "\"", "*", "&", "#", "<", ">", "=", ",", "!", "|", "+", "-", "/"] {
            let b = button(s)
            b.addAction(UIAction { [weak self] _ in self?.onSymbol?(s) }, for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
        let done = button("⌄ hide", mono: false, tint: .secondaryLabel)
        done.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        stack.addArrangedSubview(done)
    }

    @objc private func pick(_ b: UIButton) { if b.tag < pickItems.count { onPick?(pickItems[b.tag]) } }
}
