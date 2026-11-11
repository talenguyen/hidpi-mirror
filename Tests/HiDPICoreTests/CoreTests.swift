import Testing
@testable import HiDPICore

@Test func parsesSizes() {
    #expect(PointSize.parse("1600x900") == PointSize(width: 1600, height: 900))
    #expect(PointSize.parse("1280X720") == PointSize(width: 1280, height: 720))
    #expect(PointSize.parse("abc") == nil)
    #expect(PointSize.parse("1600") == nil)
    #expect(PointSize.parse("10x10") == nil)
}

@Test func backingIsDouble() {
    let s = PointSize(width: 1600, height: 900)
    #expect(s.pixelWidth == 3200 && s.pixelHeight == 1800)
}

let builtin = DisplayInfo(id: 1, vendor: 0x610, model: 1, isBuiltin: true)
let dell = DisplayInfo(id: 3, vendor: dellVendorID, model: 53463, isBuiltin: false)
let other = DisplayInfo(id: 4, vendor: 0x1234, model: 1, isBuiltin: false)
let virt = DisplayInfo(id: 9, vendor: virtualVendorID, model: 1, isBuiltin: false)

@Test func selectsDellOnly() {
    #expect(selectTarget([builtin, other, dell, virt], vendor: dellVendorID) == dell)
    #expect(selectTarget([builtin, virt], vendor: dellVendorID) == nil)
    #expect(selectTarget([builtin], vendor: nil) == nil)
}

@Test func anyVendorSkipsBuiltinAndVirtual() {
    #expect(selectTarget([builtin, virt, other], vendor: nil) == other)
}

@Test func reconcileDecisions() {
    #expect(decide(.init(targetPresent: true, virtualExists: false, targetMirrorsVirtual: false)) == .createVirtualAndMirror)
    #expect(decide(.init(targetPresent: true, virtualExists: true, targetMirrorsVirtual: false)) == .mirrorOnly)
    #expect(decide(.init(targetPresent: true, virtualExists: true, targetMirrorsVirtual: true)) == .none)
    #expect(decide(.init(targetPresent: false, virtualExists: true, targetMirrorsVirtual: false)) == .destroyVirtual)
    #expect(decide(.init(targetPresent: false, virtualExists: false, targetMirrorsVirtual: false)) == .none)
}
