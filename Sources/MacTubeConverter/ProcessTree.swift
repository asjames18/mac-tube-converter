import Darwin
import Foundation

/// Signals a process and every descendant it started (for example the ffmpeg that yt-dlp launches),
/// so cancel and quit never leave orphaned media tools running.
enum ProcessTree {
    static func descendants(of root: pid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        let capacity = size / stride + 32
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * stride
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else { return [] }
        var children: [pid_t: [pid_t]] = [:]
        for process in processes.prefix(size / stride) {
            children[process.kp_eproc.e_ppid, default: []].append(process.kp_proc.p_pid)
        }
        var result: [pid_t] = []
        var stack = [root]
        while let pid = stack.popLast() {
            for child in children[pid] ?? [] where child != pid && child > 1 && !result.contains(child) {
                result.append(child)
                stack.append(child)
            }
        }
        return result
    }

    /// Sends `signal` to the deepest descendants first, then the root.
    static func signalTree(root: pid_t, signal: Int32) {
        guard root > 1 else { return }
        for pid in descendants(of: root).reversed() { Darwin.kill(pid, signal) }
        Darwin.kill(root, signal)
    }

    /// SIGTERM now; SIGKILL anything still alive after `grace` seconds.
    static func terminateTree(root: pid_t, grace: TimeInterval = 3) {
        guard root > 1 else { return }
        let tree = descendants(of: root) + [root]
        signalTree(root: root, signal: SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            for pid in tree where Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
        }
    }

    /// Used while the app is quitting: there is no time for a grace period.
    static func killTreeNow(root: pid_t) {
        guard root > 1 else { return }
        let tree = descendants(of: root) + [root]
        signalTree(root: root, signal: SIGTERM)
        usleep(200_000)
        for pid in tree where Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
    }
}
