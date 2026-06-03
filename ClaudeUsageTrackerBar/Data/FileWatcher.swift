import Foundation
import CoreServices

final class FileWatcher {
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private let watchQueue = DispatchQueue(label: "com.yettimon.claude-usage-tracker-bar.watcher", qos: .utility)
    private let onchange: () -> Void

    init(
        path: String = ("~/.claude/projects" as NSString).expandingTildeInPath,
        onChange: @escaping () -> Void
    ) {
        self.onchange = onChange
        start(path: path)
    }

    private func start(path: String) {
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().scheduleRefresh()
        }

        guard let s = FSEventStreamCreate(
            nil,
            callback,
            &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        stream = s
        FSEventStreamSetDispatchQueue(s, watchQueue)
        FSEventStreamStart(s)
    }

    private func scheduleRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.onchange() }
        }
        debounceWorkItem = item
        watchQueue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
