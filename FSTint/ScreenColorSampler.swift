import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenColorSampler {
    static func sampleTopColumns(of application: SCRunningApplication,
                                 on display: SCDisplay,
                                 belowMenuBarHeight menuBarHeight: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        filter.includeMenuBar = false

        let sampleHeight: CGFloat = 2
        let sampleY = min(max(0, CGFloat(display.height) - sampleHeight), max(0, menuBarHeight + 2))
        let pixelScale = max(1, CGFloat(filter.pointPixelScale))

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: 0, y: sampleY, width: CGFloat(display.width), height: sampleHeight)
        configuration.width = max(1, Int(CGFloat(display.width) * pixelScale))
        configuration.height = max(1, Int(sampleHeight * pixelScale))
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = false
        configuration.showsCursor = false
        configuration.shouldBeOpaque = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB as CFString
        configuration.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        guard let rgbaImage = rgbaPixels(in: image),
              let columnPixels = medianPixelForEachColumn(rgbaImage.pixels, width: rgbaImage.width, height: rgbaImage.height),
              let columnImage = makeColumnImage(from: columnPixels)
        else {
            throw SamplingError.couldNotReadPixels
        }

        return columnImage
    }

    private static func rgbaPixels(in image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else {
                return false
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return didDraw ? (pixels, width, height) : nil
    }

    private static func medianPixelForEachColumn(_ rgbaPixels: [UInt8], width: Int, height: Int) -> [RGBPixel]? {
        guard width > 0, height > 0 else { return nil }

        var columns = [RGBPixel]()
        columns.reserveCapacity(width)

        for x in 0..<width {
            var red = [UInt8]()
            var green = [UInt8]()
            var blue = [UInt8]()
            red.reserveCapacity(height)
            green.reserveCapacity(height)
            blue.reserveCapacity(height)

            for y in 0..<height {
                let index = ((y * width) + x) * 4
                guard rgbaPixels[index + 3] > 16 else { continue }
                red.append(rgbaPixels[index])
                green.append(rgbaPixels[index + 1])
                blue.append(rgbaPixels[index + 2])
            }

            guard !red.isEmpty else {
                columns.append(columns.last ?? .black)
                continue
            }

            columns.append(RGBPixel(red: median(red), green: median(green), blue: median(blue)))
        }

        return columns
    }

    private static func makeColumnImage(from pixels: [RGBPixel]) -> CGImage? {
        var rgba = [UInt8]()
        rgba.reserveCapacity(pixels.count * 4)
        for pixel in pixels {
            rgba.append(pixel.red)
            rgba.append(pixel.green)
            rgba.append(pixel.blue)
            rgba.append(255)
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData)
        else {
            return nil
        }

        return CGImage(width: pixels.count,
                       height: 1,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: pixels.count * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    private static func median(_ values: [UInt8]) -> UInt8 {
        let sortedValues = values.sorted()
        return sortedValues[sortedValues.count / 2]
    }

    private struct RGBPixel {
        static let black = RGBPixel(red: 0, green: 0, blue: 0)

        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private enum SamplingError: Error {
        case couldNotReadPixels
    }
}
