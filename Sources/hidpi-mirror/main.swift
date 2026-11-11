import AppKit
import CoreGraphics
import CVirtualDisplay
import Foundation
import HiDPICore

let label = "local.hidpi-mirror"
let usage = """
usage: hidpi-mirror <command> [options]

  on       start the LaunchAgent (applies HiDPI to the external display)
  off      stop the LaunchAgent (restores plain native mode, removes virtual display)
  status   show displays, virtual display and mirror state
  run      run in the foreground (what the LaunchAgent executes); Ctrl-C = off

options (run, status):
  --size WxH     "looks like" size, default 1600x900
  --vendor HEX   EDID vendor of the display to scale (e.g. 10ac = Dell), default "any" = first external display
  --hz N         refresh rate of the virtual display, default 60
"""

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func fail<T>(_ message: String) -> T { die(message) }

func log(_ message: String) {
    print("[hidpi-mirror] \(message)")
    fflush(stdout)
}

// MARK: options

var size = PointSize(width: 1600, height: 900)
var vendor: UInt32? = nil  // nil = any external display
var hz = 60.0
let debug = ProcessInfo.processInfo.environment["HIDPI_MIRROR_DEBUG"] != nil

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { die(usage) }
let command = args.removeFirst()
while !args.isEmpty {
    let flag = args.removeFirst()
    func value() -> String { args.isEmpty ? fail("missing value for \(flag)") : args.removeFirst() }
    switch flag {
    case "--size": size = PointSize.parse(value()) ?? fail("bad --size (expected e.g. 1600x900)")
    case "--vendor":
        let v = value()
        vendor = v == "any" ? nil : (UInt32(v.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? fail("bad --vendor"))
    case "--hz": hz = Double(value()) ?? fail("bad --hz")
    default: die("unknown option \(flag)\n\n\(usage)")
    }
}

// MARK: CoreGraphics helpers

func onlineDisplays() -> [DisplayInfo] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return ids.prefix(Int(count)).map {
        DisplayInfo(id: $0, vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0), isBuiltin: CGDisplayIsBuiltin($0) != 0)
    }
}

func modeDescription(_ id: CGDirectDisplayID) -> String {
    guard let m = CGDisplayCopyDisplayMode(id) else { return "no mode" }
    return "looks like \(m.width)x\(m.height), backing \(m.pixelWidth)x\(m.pixelHeight) @\(Int(m.refreshRate))Hz"
}

// MARK: status

func printStatus() -> Int32 {
    let displays = onlineDisplays()
    let target = selectTarget(displays, vendor: vendor)
    let virtual = displays.first { $0.vendor == virtualVendorID }
    for d in displays {
        var tags: [String] = []
        if d.isBuiltin { tags.append("built-in") }
        if d.vendor == virtualVendorID { tags.append("hidpi-mirror virtual") }
        if d.id == target?.id { tags.append("target") }
        let master = CGDisplayMirrorsDisplay(d.id)
        if master != 0 { tags.append("mirrors \(master)") }
        print("display \(d.id) vendor=0x\(String(d.vendor, radix: 16)) model=\(d.model) [\(tags.joined(separator: ", "))]: \(modeDescription(d.id))")
    }
    let active = target != nil && virtual != nil && CGDisplayMirrorsDisplay(target!.id) == virtual!.id
    print(active ? "state: ON (target mirrors virtual display)" : "state: OFF")
    return active ? 0 : 3
}

// MARK: launchctl wrappers (on / off)

let uid = getuid()
let domain = "gui/\(uid)"
let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"

@discardableResult
func launchctl(_ arguments: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = arguments
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

func isLoaded() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = ["print", "\(domain)/\(label)"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

// MARK: run (daemon)

final class Daemon {
    var handle: UnsafeMutableRawPointer?
    var virtualID: CGDirectDisplayID = 0
    var pending: DispatchWorkItem?
    var stopping = false

    func observe() -> (Observation, DisplayInfo?) {
        let target = selectTarget(onlineDisplays(), vendor: vendor)
        let mirrors = target.map { virtualID != 0 && CGDisplayMirrorsDisplay($0.id) == virtualID } ?? false
        return (Observation(targetPresent: target != nil, virtualExists: handle != nil, targetMirrorsVirtual: mirrors), target)
    }

    func createVirtual() -> Bool {
        var id: CGDirectDisplayID = 0
        guard let h = dh_vd_create("HiDPI Mirror \(size.width)x\(size.height)", UInt32(size.width), UInt32(size.height), hz,
                                   virtualVendorID, virtualProductID, 1, &id) else {
            log("failed to create virtual display (private API unavailable or rejected)")
            return false
        }
        handle = h
        virtualID = id
        log("created virtual display \(id) (\(size.width)x\(size.height) HiDPI)")
        return true
    }

    func destroyVirtual() {
        guard handle != nil else { return }
        dh_vd_destroy(handle)
        handle = nil
        log("destroyed virtual display \(virtualID)")
        virtualID = 0
    }

    func setMirror(target: CGDirectDisplayID, master: CGDirectDisplayID) -> Bool {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        guard CGConfigureDisplayMirrorOfDisplay(cfg, target, master) == .success else {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        // forSession: nothing is written to the display prefs; a dead daemon leaves no stale mirror.
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }

    func reconcile() {
        guard !stopping else { return }
        let (obs, target) = observe()
        if debug { log("reconcile: \(obs) -> \(decide(obs)) master=\(target.map { CGDisplayMirrorsDisplay($0.id) } ?? 0)") }
        switch decide(obs) {
        case .none: break
        case .destroyVirtual:
            destroyVirtual()
        case .createVirtualAndMirror:
            guard createVirtual() else { return }
            // The virtual display needs a moment to come online before it can be a mirror master.
            schedule(after: 0.8)
        case .mirrorOnly:
            guard let target = target else { return }
            if setMirror(target: target.id, master: virtualID) {
                log("mirroring display \(target.id) from virtual \(virtualID)")
            } else {
                log("mirror request failed; will retry on next change")
            }
        }
    }

    func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func stop() {
        stopping = true
        pending?.cancel()
        if let target = selectTarget(onlineDisplays(), vendor: vendor), CGDisplayMirrorsDisplay(target.id) != 0 {
            _ = setMirror(target: target.id, master: kCGNullDirectDisplay)
            log("released mirror on display \(target.id)")
        }
        destroyVirtual()
        // Give WindowServer a moment to apply the teardown before the process exits.
        Thread.sleep(forTimeInterval: 0.5)
        log("stopped")
        exit(0)
    }
}

func runDaemon() -> Never {
    let daemon = Daemon()
    let callback: CGDisplayReconfigurationCallBack = { did, flags, userInfo in
        if debug { log("callback display=\(did) flags=\(flags.rawValue)") }
        guard !flags.contains(.beginConfigurationFlag), let userInfo = userInfo else { return }
        let d = Unmanaged<Daemon>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async { d.schedule(after: 1.5) }
    }
    CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(daemon).toOpaque())

    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { daemon.stop() }
        src.resume()
        signalSources.append(src)
    }
    log("started (size \(size.width)x\(size.height), vendor \(vendor.map { "0x" + String($0, radix: 16) } ?? "any"))")
    daemon.schedule(after: 0.1)
    // Safety net in case a reconfiguration callback is missed (e.g. across sleep/wake).
    let heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in daemon.reconcile() }
    // A headless NSApplication connects us to WindowServer so display changes made by
    // other processes (cable unplug/replug) are delivered; without it CG state goes stale.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    withExtendedLifetime(heartbeat) { app.run() }
    exit(0)
}
var signalSources: [DispatchSourceSignal] = []

// MARK: dispatch

switch command {
case "run": runDaemon()
case "status": exit(printStatus())
case "on":
    guard FileManager.default.fileExists(atPath: plistPath) else { die("LaunchAgent not installed; run scripts/install.sh (or use `hidpi-mirror run`)") }
    if isLoaded() { launchctl(["kickstart", "\(domain)/\(label)"]) } else { launchctl(["bootstrap", domain, plistPath]) }
    print("started \(label)")
case "off":
    if isLoaded() {
        launchctl(["bootout", "\(domain)/\(label)"])
        print("stopped \(label) (virtual display removed, native mode restored)")
    } else {
        print("\(label) not running")
    }
case "help", "-h", "--help": print(usage)
default: die(usage)
}
