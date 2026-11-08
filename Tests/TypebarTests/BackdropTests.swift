import AppKit
import Testing
@testable import Typebar

@MainActor
@Test func backgroundFadesToTransparentEdgesWithoutWhiteCorners() throws {
    let padding = ShadowBackdropView.contentPadding
    let image = try #require(ShadowBackdropView.backdrop(
        size: CGSize(width: 980 + padding * 2, height: ShadowBackdropView.contentHeight + padding * 2), scale: 1))
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: &pixels, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
        let offset = (y * width + x) * 4
        return pixels[offset..<(offset + 4)]
    }
    for point in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
        #expect(pixel(point.0, point.1).last == 0)
    }
    let alphas = [0, 24, 48, 72, 120, width / 2].map { Int(pixel($0, height / 2).last!) }
    #expect(alphas.first! <= 1)
    #expect(alphas.last! > 140 && alphas.last! < 180)
    #expect(zip(alphas, alphas.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(alphas[1] > alphas[0] && alphas[2] > alphas[1])
    #expect(pixel(width / 2, height / 2).dropLast().allSatisfy { $0 == 0 })
    #expect(Int(pixel(width / 2, Int(padding)).last!) >= 145)
    #expect(Int(pixel(width / 2, height - Int(padding)).last!) >= 145)
}
