#!/usr/bin/env swift

import AppKit
import Foundation

struct Options {
    var inputPath: String?
    var outputPath: String?
    var overlayPath: String
    var x: CGFloat?
    var y: CGFloat = 0
    var targetWidth: CGFloat?
    var targetHeight: CGFloat?
    var requireFullscreen: Bool = true
}

enum OptionError: Error, CustomStringConvertible {
    case missingOutput
    case missingInput
    case badValue(String)

    var description: String {
        switch self {
        case .missingOutput:
            return "Missing required --output <path>."
        case .missingInput:
            return "Missing required --input <path>."
        case .badValue(let flag):
            return "Invalid value for \(flag)."
        }
    }
}

func defaultOverlayPath() -> String {
    let cwd = FileManager.default.currentDirectoryPath
    return "\(cwd)/AIIslandApp/Resources/Hardware/macbook-pro-14-notch-shape-reference.png"
}

func parseOptions(arguments: [String]) throws -> Options {
    var options = Options(overlayPath: defaultOverlayPath())
    var index = 0

    func nextValue(for flag: String) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw OptionError.badValue(flag)
        }
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--input":
            options.inputPath = try nextValue(for: argument)
        case "--output":
            options.outputPath = try nextValue(for: argument)
        case "--overlay":
            options.overlayPath = try nextValue(for: argument)
        case "--x":
            guard let value = Double(try nextValue(for: argument)) else {
                throw OptionError.badValue(argument)
            }
            options.x = CGFloat(value)
        case "--y":
            guard let value = Double(try nextValue(for: argument)) else {
                throw OptionError.badValue(argument)
            }
            options.y = CGFloat(value)
        case "--target-height":
            guard let value = Double(try nextValue(for: argument)) else {
                throw OptionError.badValue(argument)
            }
            options.targetHeight = CGFloat(value)
        case "--target-width":
            guard let value = Double(try nextValue(for: argument)) else {
                throw OptionError.badValue(argument)
            }
            options.targetWidth = CGFloat(value)
        case "--allow-crop":
            options.requireFullscreen = false
        default:
            throw OptionError.badValue(argument)
        }

        index += 1
    }

    guard options.outputPath != nil else {
        throw OptionError.missingOutput
    }

    guard options.inputPath != nil else {
        throw OptionError.missingInput
    }

    return options
}

func bitmapRep(size: CGSize) -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
}

func compositeOverlay(options: Options) throws {
    let inputURL = URL(fileURLWithPath: options.inputPath!)
    let outputURL = URL(fileURLWithPath: options.outputPath!)
    let overlayURL = URL(fileURLWithPath: options.overlayPath)

    guard let baseImage = NSImage(contentsOf: inputURL) else {
        throw NSError(domain: "overlay_notch_review", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unable to load input image at \(inputURL.path)"
        ])
    }

    guard let overlayImage = NSImage(contentsOf: overlayURL) else {
        throw NSError(domain: "overlay_notch_review", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Unable to load overlay image at \(overlayURL.path)"
        ])
    }

    let canvasSize = baseImage.size
    let pixelRep = NSBitmapImageRep(data: baseImage.tiffRepresentation ?? Data())
    if options.requireFullscreen {
        let expectedPoints = CGSize(width: 1512, height: 982)
        let pixelWidth = pixelRep?.pixelsWide ?? Int(canvasSize.width)
        let pixelHeight = pixelRep?.pixelsHigh ?? Int(canvasSize.height)
        guard abs(canvasSize.width - expectedPoints.width) < 0.5, abs(canvasSize.height - expectedPoints.height) < 0.5 else {
            throw NSError(domain: "overlay_notch_review", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Full-screen review is required. Expected \(Int(expectedPoints.width))x\(Int(expectedPoints.height)) points, got \(Int(canvasSize.width))x\(Int(canvasSize.height)) points (\(pixelWidth)x\(pixelHeight) px)."
            ])
        }
    }

    let overlayAspect = overlayImage.size.width / overlayImage.size.height
    let overlaySize: CGSize
    if let targetWidth = options.targetWidth {
        overlaySize = CGSize(width: targetWidth, height: targetWidth / overlayAspect)
    } else if let targetHeight = options.targetHeight {
        overlaySize = CGSize(width: targetHeight * overlayAspect, height: targetHeight)
    } else {
        overlaySize = CGSize(width: 370, height: 64)
    }
    let overlayX = options.x ?? ((canvasSize.width - overlaySize.width) / 2)
    let overlayRect = CGRect(
        x: overlayX,
        y: canvasSize.height - options.y - overlaySize.height,
        width: overlaySize.width,
        height: overlaySize.height
    )

    guard let rep = bitmapRep(size: canvasSize) else {
        throw NSError(domain: "overlay_notch_review", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create bitmap context."
        ])
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "overlay_notch_review", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create graphics context."
        ])
    }

    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
    baseImage.draw(in: CGRect(origin: .zero, size: canvasSize))
    overlayImage.draw(in: overlayRect)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "overlay_notch_review", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Unable to encode PNG."
        ])
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
    print(outputURL.path)
}

do {
    let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    try compositeOverlay(options: options)
} catch {
    fputs("overlay_notch_review.swift: \(error)\n", stderr)
    exit(1)
}
