// 生成 App 图标（1024 主图 + 各尺寸），输出到 Sources/Resources/Assets.xcassets/AppIcon.appiconset
// 用法: swift -module-cache-path .build/modulecache scripts/make_icon.swift
import AppKit

let canvas: CGFloat = 1024
let inset: CGFloat = 100          // macOS 图标四周留白
let bodyRect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let bodyRadius: CGFloat = 188

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

// 阴影
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()

let body = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRadius, yRadius: bodyRadius)
NSColor.black.setFill()
body.fill()

NSGraphicsContext.current?.saveGraphicsState()
NSShadow().set()

// 主体渐变
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.22, blue: 0.55, alpha: 1),
    NSColor(srgbRed: 0.45, green: 0.27, blue: 0.80, alpha: 1)
])!
gradient.draw(in: body, angle: -90)

// 左上角柔光（整块区域绘制，避免出现接缝）
NSGraphicsContext.saveGraphicsState()
body.addClip()
let glow = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.20),
    NSColor.white.withAlphaComponent(0.0)
])!
glow.draw(in: bodyRect, relativeCenterPosition: NSPoint(x: -0.45, y: 0.5))
NSGraphicsContext.restoreGraphicsState()

// 笔记本（描边屏幕 + 底座）
NSColor.white.setStroke()
NSColor.white.setFill()
let screen = NSBezierPath(
    roundedRect: NSRect(x: 512 - 235, y: 386, width: 470, height: 322),
    xRadius: 42, yRadius: 42
)
screen.lineWidth = 26
screen.stroke()

let base = NSBezierPath(
    roundedRect: NSRect(x: 512 - 296, y: 342, width: 592, height: 36),
    xRadius: 18, yRadius: 18
)
base.fill()

// 右下角「保持唤醒」状态点
let dotCenter = NSPoint(x: 512 + 250, y: 322)
let dotRadius: CGFloat = 42
let dotRect = NSRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
NSColor.white.setFill()
NSBezierPath(ovalIn: dotRect.insetBy(dx: -10, dy: -10)).fill()
NSColor(srgbRed: 0.24, green: 0.86, blue: 0.52, alpha: 1).setFill()
NSBezierPath(ovalIn: dotRect).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Sources/Resources/Assets.xcassets")
let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

// 1024 主图放在 .build 下，不进资源目录（否则 xcodebuild 会警告 "unassigned child"）
let stage = root.appendingPathComponent(".build/icon")
try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

let master = stage.appendingPathComponent("icon_1024.png")
try png.write(to: master)

struct Entry { let size: Int; let scale: Int; var pixels: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)@\(scale)x.png" } }

let entries = [
    Entry(size: 16, scale: 1), Entry(size: 16, scale: 2),
    Entry(size: 32, scale: 1), Entry(size: 32, scale: 2),
    Entry(size: 128, scale: 1), Entry(size: 128, scale: 2),
    Entry(size: 256, scale: 1), Entry(size: 256, scale: 2),
    Entry(size: 512, scale: 1), Entry(size: 512, scale: 2)
]

for entry in entries {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = [
        "-z", "\(entry.pixels)", "\(entry.pixels)",
        master.path,
        "--out", iconSet.appendingPathComponent(entry.filename).path
    ]
    try? task.run()
    task.waitUntilExit()
}

let contents: [String: Any] = [
    "images": entries.map { entry in
        ["filename": entry.filename, "idiom": "mac", "scale": "\(entry.scale)x", "size": "\(entry.size)x\(entry.size)"]
    },
    "info": ["author": "xcode", "version": 1]
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: iconSet.appendingPathComponent("Contents.json"))

let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: assets.appendingPathComponent("Contents.json"))

print("icon generated: \(master.path)")
