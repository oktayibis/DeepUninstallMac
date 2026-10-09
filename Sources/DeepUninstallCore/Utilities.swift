import Foundation

/// Thread-safe fixed-size result buffer used by `Parallel.map`.
private final class ResultBox<R>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [R?]
    init(count: Int) { storage = Array(repeating: nil, count: count) }
    func set(_ index: Int, _ value: R) { lock.lock(); storage[index] = value; lock.unlock() }
    var values: [R] { storage.map { $0! } }
}

public enum Parallel {
    /// Order-preserving concurrent map for blocking file-system work.
    public static func map<T: Sendable, R>(_ input: [T], _ transform: @Sendable (T) -> R) -> [R] {
        guard !input.isEmpty else { return [] }
        let box = ResultBox<R>(count: input.count)
        DispatchQueue.concurrentPerform(iterations: input.count) { i in
            box.set(i, transform(input[i]))
        }
        return box.values
    }
}

public enum FileSize {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Allocated on-disk size of a file or (recursively) a directory. Unreadable parts count as 0.
    public static func of(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true || values.isSymbolicLink == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        )
        while let file = enumerator?.nextObject() as? URL {
            guard let v = try? file.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}

extension URL {
    var isDirectoryURL: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// `/Users/me/Library/Caches/x` → `~/Library/Caches/x`
    public var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
