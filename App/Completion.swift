import Foundation

enum CompletionKind { case function, type, constant, keyword, snippet, local }

struct CompletionItem: Hashable {
    let name: String
    let detail: String          // signature or short description
    let kind: CompletionKind
    let insert: String          // text inserted (without caret handling)
    let hasParams: Bool
}

/// Indexes raylib.h / raymath.h / rlgl.h (bundled, or the copies you downloaded/imported into
/// Documents/Headers) and offers prefix completion + signature help.
final class CompletionEngine {
    static let shared = CompletionEngine()

    private(set) var items: [CompletionItem] = []
    private var byName: [String: CompletionItem] = [:]
    private(set) var functionRegex: NSRegularExpression?
    private(set) var typeRegex: NSRegularExpression?
    private(set) var constantRegex: NSRegularExpression?
    private(set) var headerInfo = "bundled headers"

    private static let keywords = ["auto","break","case","char","const","continue","default","do","double","else","enum","extern",
        "float","for","goto","if","inline","int","long","register","return","short","signed","sizeof","static","struct",
        "switch","typedef","union","unsigned","void","volatile","while","bool","true","false","NULL"]

    private static let libc: [(String, String)] = [
        ("printf","int printf(const char *fmt, ...)"), ("sprintf","int sprintf(char *buf, const char *fmt, ...)"),
        ("snprintf","int snprintf(char *buf, size_t n, const char *fmt, ...)"), ("malloc","void *malloc(size_t size)"),
        ("calloc","void *calloc(size_t n, size_t size)"), ("realloc","void *realloc(void *p, size_t size)"),
        ("free","void free(void *p)"), ("memcpy","void *memcpy(void *dst, const void *src, size_t n)"),
        ("memset","void *memset(void *p, int c, size_t n)"), ("strlen","size_t strlen(const char *s)"),
        ("strcmp","int strcmp(const char *a, const char *b)"), ("strcpy","char *strcpy(char *dst, const char *src)"),
        ("sinf","float sinf(float x)"), ("cosf","float cosf(float x)"), ("sqrtf","float sqrtf(float x)"),
        ("powf","float powf(float x, float y)"), ("fabsf","float fabsf(float x)"), ("floorf","float floorf(float x)"),
        ("atan2f","float atan2f(float y, float x)"), ("rand","int rand(void)"), ("srand","void srand(unsigned seed)"),
        ("time","time_t time(time_t *t)"), ("abs","int abs(int x)"), ("qsort","void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))"),
    ]

    private static let snippets: [(String, String, String)] = [
        ("main", "int main(void) { … }", "int main(void)\n{\n    InitWindow(800, 450, \"raylib\");\n    SetTargetFPS(60);\n\n    while (!WindowShouldClose())\n    {\n        BeginDrawing();\n            ClearBackground(RAYWHITE);\n        EndDrawing();\n    }\n\n    CloseWindow();\n    return 0;\n}\n"),
        ("for", "for loop", "for (int i = 0; i < 10; i++)\n{\n    \n}"),
        ("while", "while loop", "while ()\n{\n    \n}"),
        ("#include", "#include \"raylib.h\"", "#include \"raylib.h\""),
        ("#include <raymath.h>", "raymath", "#include \"raymath.h\""),
    ]

    init() { reload(overrideDir: nil) }

    func reload(overrideDir: URL?) {
        var out: [CompletionItem] = []
        var dirs: [URL] = []
        var info = "bundled headers"
        if let o = overrideDir,
           FileManager.default.fileExists(atPath: o.appendingPathComponent("raylib.h").path) {
            dirs.append(o); info = "headers from Documents/Headers"
        }
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("include")) }

        var seen = Set<String>()
        for header in ["raylib.h", "raymath.h", "rlgl.h"] {
            guard let dir = dirs.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent(header).path) }),
                  let text = try? String(contentsOf: dir.appendingPathComponent(header), encoding: .utf8) else { continue }
            Self.parse(text, into: &out, seen: &seen)
        }
        for k in Self.keywords { out.append(CompletionItem(name: k, detail: "keyword", kind: .keyword, insert: k, hasParams: false)) }
        for (n, sig) in Self.libc { out.append(CompletionItem(name: n, detail: sig, kind: .function, insert: n, hasParams: !sig.hasSuffix("(void)"))) }
        for (n, d, body) in Self.snippets { out.append(CompletionItem(name: n, detail: d, kind: .snippet, insert: body, hasParams: false)) }

        items = out
        byName = Dictionary(out.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        headerInfo = info
        functionRegex = Self.alternation(out.filter { $0.kind == .function }.map { $0.name })
        typeRegex = Self.alternation(out.filter { $0.kind == .type }.map { $0.name })
        constantRegex = Self.alternation(out.filter { $0.kind == .constant }.map { $0.name })
    }

    private static func alternation(_ names: [String]) -> NSRegularExpression? {
        guard !names.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: "\\b(?:" + names.joined(separator: "|") + ")\\b")
    }

    private static func parse(_ text: String, into out: inout [CompletionItem], seen: inout Set<String>) {
        func add(_ it: CompletionItem) { if seen.insert(it.name).inserted { out.append(it) } }

        let fn = try! NSRegularExpression(pattern: #"^\s*(?:RLAPI|RMAPI)\s+(.+?)\b([A-Za-z_]\w*)\s*\(([^)]*)\)"#, options: [.anchorsMatchLines])
        let typ = try! NSRegularExpression(pattern: #"^\}\s*([A-Za-z_]\w*)\s*;|^typedef\s+[\w\s\*]+?\s+([A-Za-z_]\w*)\s*;"#, options: [.anchorsMatchLines])
        let enm = try! NSRegularExpression(pattern: #"^\s+([A-Z][A-Z0-9_]{2,})\s*(?:=[^,/]*)?,"#, options: [.anchorsMatchLines])
        let def = try! NSRegularExpression(pattern: #"^#define\s+([A-Z][A-Z0-9_]{2,})\b"#, options: [.anchorsMatchLines])
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)

        fn.enumerateMatches(in: text, range: all) { m, _, _ in
            guard let m = m else { return }
            let ret = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let name = ns.substring(with: m.range(at: 2))
            let params = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            let hasParams = !(params.isEmpty || params == "void")
            add(CompletionItem(name: name, detail: "\(ret) \(name)(\(params))", kind: .function, insert: name, hasParams: hasParams))
        }
        typ.enumerateMatches(in: text, range: all) { m, _, _ in
            guard let m = m else { return }
            for g in 1...2 where m.range(at: g).location != NSNotFound {
                let n = ns.substring(with: m.range(at: g))
                add(CompletionItem(name: n, detail: "type", kind: .type, insert: n, hasParams: false))
            }
        }
        enm.enumerateMatches(in: text, range: all) { m, _, _ in
            guard let m = m else { return }
            let n = ns.substring(with: m.range(at: 1))
            add(CompletionItem(name: n, detail: "constant", kind: .constant, insert: n, hasParams: false))
        }
        def.enumerateMatches(in: text, range: all) { m, _, _ in
            guard let m = m else { return }
            let n = ns.substring(with: m.range(at: 1))
            add(CompletionItem(name: n, detail: "macro", kind: .constant, insert: n, hasParams: false))
        }
    }

    // MARK: Queries

    func completions(prefix: String, document: String, limit: Int = 24) -> [CompletionItem] {
        guard !prefix.isEmpty else { return [] }
        let p = prefix.lowercased()
        var scored: [(Int, CompletionItem)] = []
        for it in items {
            let n = it.name.lowercased()
            if n == p && it.name == prefix { continue }
            if n.hasPrefix(p) { scored.append((rank(it, 0), it)) }
            else if p.count >= 3 && n.contains(p) { scored.append((rank(it, 50), it)) }
        }
        // identifiers already used in this file
        var locals = Set<String>()
        if let re = try? NSRegularExpression(pattern: #"\b[A-Za-z_]\w{2,}\b"#) {
            let ns = document as NSString
            re.enumerateMatches(in: document, range: NSRange(location: 0, length: min(ns.length, 60_000))) { m, _, _ in
                if let m = m { locals.insert(ns.substring(with: m.range)) }
            }
        }
        for l in locals where l.lowercased().hasPrefix(p) && l != prefix && byName[l] == nil {
            scored.append((20, CompletionItem(name: l, detail: "in this file", kind: .local, insert: l, hasParams: false)))
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.name.count < $1.1.name.count }
            .prefix(limit).map { $0.1 }
    }

    private func rank(_ it: CompletionItem, _ base: Int) -> Int {
        switch it.kind {
        case .function, .type: return base
        case .constant: return base + 5
        case .snippet: return base + 2
        case .local: return base + 20
        case .keyword: return base + 8
        }
    }

    func lookup(_ name: String) -> CompletionItem? { byName[name] }

    /// Signature of the call the caret is inside of, e.g. "void DrawCircle(int x, int y, float r, Color c)"
    func signatureHelp(text: String, caret: Int) -> String? {
        let chars = Array(text.utf16)
        var depth = 0
        var i = min(caret, chars.count) - 1
        while i >= 0 {
            let c = chars[i]
            if c == 0x29 { depth += 1 }                       // )
            else if c == 0x28 {                               // (
                if depth == 0 {
                    var j = i - 1
                    while j >= 0, chars[j] == 0x20 { j -= 1 }
                    var end = j
                    while j >= 0, Self.isIdent(chars[j]) { j -= 1 }
                    if end > j {
                        let name = String(utf16CodeUnits: Array(chars[(j+1)...end]), count: end - j)
                        if let it = byName[name], it.kind == .function { return it.detail }
                    }
                    end = -1
                    return nil
                }
                depth -= 1
            } else if c == 0x3B || c == 0x7B || c == 0x7D { return nil }   // ; { }
            i -= 1
        }
        return nil
    }

    static func isIdent(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }
}
