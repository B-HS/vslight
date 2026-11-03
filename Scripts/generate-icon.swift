import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appending(path: "Resources")
let assetDirectory = root.appending(path: "Sources/Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)

_ = NSApplication.shared

let canvas = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let context = NSGraphicsContext.current else {
    exit(1)
}
context.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 20, dy: 20), xRadius: 220, yRadius: 220)
tile.addClip()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.08, green: 0.12, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.42, blue: 0.68, alpha: 1)
])
gradient?.draw(in: tile, angle: -55)

let glow = NSBezierPath(ovalIn: NSRect(x: -160, y: 540, width: 1080, height: 760))
NSColor.white.withAlphaComponent(0.12).setFill()
glow.fill()

let halo = NSBezierPath(ovalIn: NSRect(x: 202, y: 202, width: 620, height: 620))
NSColor.white.withAlphaComponent(0.97).setFill()
halo.fill()

let symbolColor = NSColor(srgbRed: 0.08, green: 0.14, blue: 0.34, alpha: 1)
let configuration = NSImage.SymbolConfiguration(pointSize: 320, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    symbol.isTemplate = true
    let maxSide: CGFloat = 380
    let scale = min(maxSide / symbol.size.width, maxSide / symbol.size.height)
    let width = symbol.size.width * scale
    let height = symbol.size.height * scale
    let target = NSRect(
        x: (CGFloat(canvas) - width) / 2,
        y: (CGFloat(canvas) - height) / 2,
        width: width,
        height: height
    )
    symbolColor.set()
    symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:])
else {
    exit(1)
}

let masterURL = resources.appending(path: "icon-1024.png")
try png.write(to: masterURL, options: .atomic)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (pixelSize, name) in sizes {
    let destination = assetDirectory.appending(path: name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(pixelSize)", "\(pixelSize)", masterURL.path, "--out", destination.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
}

let readmeIcon = resources.appending(path: "icon.png")
let readmeProcess = Process()
readmeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
readmeProcess.arguments = ["-z", "200", "200", masterURL.path, "--out", readmeIcon.path]
readmeProcess.standardOutput = FileHandle.nullDevice
readmeProcess.standardError = FileHandle.nullDevice
try readmeProcess.run()
readmeProcess.waitUntilExit()

let contents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: assetDirectory.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Generated icon assets at \(assetDirectory.path)")
