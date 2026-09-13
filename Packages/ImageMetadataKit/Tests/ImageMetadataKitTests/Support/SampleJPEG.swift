// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fabrique un JPEG minuscule à la volée.
///
/// Préféré à une image versionnée : la fixture ne peut pas diverger du test,
/// et le dépôt reste sans binaire.
enum SampleJPEG {

    enum Failure: Error {
        case contextCreationFailed
        case encodingFailed
    }

    static func make(width: Int = 16, height: Int = 12) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw Failure.contextCreationFailed
        }

        context.setFillColor(red: 0.16, green: 0.36, blue: 0.55, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else { throw Failure.encodingFailed }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }
}
