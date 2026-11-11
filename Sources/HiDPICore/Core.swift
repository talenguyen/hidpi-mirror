import Foundation

/// "Looks like" size in points, e.g. 1600x900.
public struct PointSize: Equatable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }

    /// Backing-store size of a HiDPI (2x) mode.
    public var pixelWidth: Int { width * 2 }
    public var pixelHeight: Int { height * 2 }

    /// Parses "1600x900" (also "1600X900", "1600*900").
    public static func parse(_ text: String) -> PointSize? {
        let parts = text.lowercased().split(whereSeparator: { $0 == "x" || $0 == "*" })
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]),
              w >= 640, h >= 360, w <= 4096, h <= 2304 else { return nil }
        return PointSize(width: w, height: h)
    }
}

/// Minimal description of an online display, decoupled from CoreGraphics for testing.
public struct DisplayInfo: Equatable {
    public let id: UInt32
    public let vendor: UInt32
    public let model: UInt32
    public let isBuiltin: Bool
    public init(id: UInt32, vendor: UInt32, model: UInt32, isBuiltin: Bool) {
        self.id = id; self.vendor = vendor; self.model = model; self.isBuiltin = isBuiltin
    }
}

/// Vendor ID we give our own virtual display so we can always recognise (and skip) it.
public let virtualVendorID: UInt32 = 0x7D11
public let virtualProductID: UInt32 = 0x0001
/// EDID vendor ID of Dell Inc. (0x10AC).
public let dellVendorID: UInt32 = 0x10AC

/// Picks the physical display to scale: first external display from `vendor`
/// (any external display when `vendor` is nil). Never the built-in, never our virtual display.
public func selectTarget(_ displays: [DisplayInfo], vendor: UInt32?) -> DisplayInfo? {
    displays.first { d in
        !d.isBuiltin && d.vendor != virtualVendorID && (vendor == nil || d.vendor == vendor)
    }
}

/// What the reconcile loop observed.
public struct Observation: Equatable {
    public var targetPresent: Bool
    public var virtualExists: Bool
    public var targetMirrorsVirtual: Bool
    public init(targetPresent: Bool, virtualExists: Bool, targetMirrorsVirtual: Bool) {
        self.targetPresent = targetPresent
        self.virtualExists = virtualExists
        self.targetMirrorsVirtual = targetMirrorsVirtual
    }
}

public enum Action: Equatable {
    case none
    case createVirtualAndMirror
    case mirrorOnly
    case destroyVirtual
}

/// Idempotent decision: converge on "virtual display exists iff the target is plugged in,
/// and the target mirrors it".
public func decide(_ o: Observation) -> Action {
    switch (o.targetPresent, o.virtualExists, o.targetMirrorsVirtual) {
    case (false, true, _): return .destroyVirtual
    case (false, false, _): return .none
    case (true, false, _): return .createVirtualAndMirror
    case (true, true, false): return .mirrorOnly
    case (true, true, true): return .none
    }
}
