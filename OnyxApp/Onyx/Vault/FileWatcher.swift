import Foundation

final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let debounceInterval: TimeInterval
    private var debounceTask: Task<Void, Never>?
    private var onChange: (() -> Void)?

    init(path: String, debounceInterval: TimeInterval = 0.2) {
        self.path = path
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let pathCF = path as CFString
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            fileWatcherCallback,
            &context,
            [pathCF] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceTask?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        onChange = nil
    }

    fileprivate func handleEvent() {
        debounceTask?.cancel()
        let interval = debounceInterval
        let callback = onChange
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
            guard !Task.isCancelled else { return }
            callback?()
        }
    }
}

private func fileWatcherCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
    watcher.handleEvent()
}
