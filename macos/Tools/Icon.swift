import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = NSImage(contentsOfFile: CommandLine.arguments[2]) else { fatalError("Missing generated app icon") }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}

// Modern ICNS stores these PNG representations in a small typed container.
// Write it directly so packaging does not depend on iconutil's system service.
func uint32(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let representations = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
]
var body = Data()
for (type, name) in representations {
    let png = try Data(contentsOf: destination.appendingPathComponent(name))
    body.append(Data(type.utf8)); body.append(uint32(png.count + 8)); body.append(png)
}
var icon = Data("icns".utf8)
icon.append(uint32(body.count + 8)); icon.append(body)
let iconURL = URL(fileURLWithPath: CommandLine.arguments[3])
try icon.write(to: iconURL)
guard let decoded = NSImage(contentsOf: iconURL), decoded.isValid else {
    fatalError("macOS could not decode the packaged app icon")
}
