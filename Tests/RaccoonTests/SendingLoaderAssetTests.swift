import Foundation
import Lottie
@testable import Raccoon
import Testing

/// The bundled raccoon-rocket.json and its boundary (e-where-it-breaks.md, Sending loader).
@MainActor
struct SendingLoaderAssetTests {
    @Test func `the bundled animation is 120 frames at 60 fps`() throws {
        let animation = try #require(SendingLoaderAsset.animation(from: SendingLoaderAsset.bundledData()))
        #expect(animation.endFrame - animation.startFrame == 120)
        #expect(animation.framerate == 60)
    }

    @Test func `the Fly pose is a frame inside the animation`() throws {
        let animation = try #require(SendingLoaderAsset.animation(from: SendingLoaderAsset.bundledData()))
        #expect(SendingLoaderAsset.flyFrame == 72)
        #expect((animation.startFrame...animation.endFrame).contains(SendingLoaderAsset.flyFrame))
    }

    @Test(arguments: [nil, Data(), Data("not lottie".utf8), Data(#"{"v":"5.7.0"}"#.utf8)])
    func `a missing or undecodable file gives no animation`(data: Data?) {
        #expect(SendingLoaderAsset.animation(from: data) == nil)
    }
}
