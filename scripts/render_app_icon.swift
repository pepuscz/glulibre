#!/usr/bin/env swift
// Original GluLibre vector geometry; run from the repository root on macOS.
import AppKit

enum Segment {
    case move(CGFloat, CGFloat), line(CGFloat, CGFloat)
    case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
}
let segments: [Segment] = [
    .move(715, 302), .curve(660, 248, 590, 230, 512, 230),
    .curve(356, 230, 230, 356, 230, 512), .curve(230, 668, 356, 794, 512, 794),
    .curve(668, 794, 794, 668, 794, 512), .line(698, 512),
    .curve(673, 512, 674, 430, 638, 430), .curve(602, 430, 603, 560, 570, 560),
    .curve(540, 560, 542, 512, 508, 512)
]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("xdrip.xcodeproj/project.pbxproj").path) else {
    fatalError("Run this script from the GluLibre repository root.")
}
let brand = root.appendingPathComponent("docs/brand")
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
let path = CGMutablePath()
var svgPath = ""
for segment in segments {
    switch segment {
    case let .move(x, y):
        path.move(to: CGPoint(x: x, y: y)); svgPath += "M\(x) \(y) "
    case let .line(x, y):
        path.addLine(to: CGPoint(x: x, y: y)); svgPath += "L\(x) \(y) "
    case let .curve(x1, y1, x2, y2, x, y):
        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        svgPath += "C\(x1) \(y1) \(x2) \(y2) \(x) \(y) "
    }
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-label="GluLibre">
  <rect width="1024" height="1024" fill="#0C7F76"/>
  <path d="\(svgPath.trimmingCharacters(in: .whitespaces))" fill="none" stroke="white" stroke-width="72" stroke-linecap="round" stroke-linejoin="round"/>
</svg>

"""
try svg.write(to: brand.appendingPathComponent("glulibre.svg"), atomically: true, encoding: .utf8)

func png(size: Int) -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(colorSpace: colorSpace, components: [12.0/255, 127.0/255, 118.0/255, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    context.addPath(path)
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(72); context.setLineCap(.round); context.setLineJoin(.round)
    context.strokePath()
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}
let catalogs = ["xDrip/Resources/Assets.xcassets/AppIcon.appiconset",
                "xDrip Watch App/Assets.xcassets/AppIcon.appiconset",
                "xDrip Watch Complication/Assets.xcassets/AppIcon.appiconset",
                "xDrip Widget/Assets.xcassets/AppIcon.appiconset"]
for catalog in catalogs {
    let directory = root.appendingPathComponent(catalog)
    let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
    for entry in contents["images"] as! [[String: String]] {
        guard let filename = entry["filename"], let dimension = entry["size"]?.split(separator: "x").first,
              let points = Double(dimension) else { continue }
        let scale = Double((entry["scale"] ?? "1x").dropLast())!
        try png(size: Int(points * scale)).write(to: directory.appendingPathComponent(filename))
    }
}
try png(size: 1024).write(to: brand.appendingPathComponent("glulibre.png"))
print("Rendered GluLibre SVG, preview and all four app-icon catalogs.")
