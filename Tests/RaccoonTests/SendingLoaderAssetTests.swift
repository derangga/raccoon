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

    /// The loader stays vector: no image asset, so nothing in it is a bitmap that blurs when scaled.
    @Test func `the bundled animation holds no bitmap`() throws {
        let data = try #require(SendingLoaderAsset.bundledData())
        #expect(SendingLoaderAsset.isVectorOnly(data))
    }

    @Test func `an animation that embeds an image is not vector only`() {
        let json = """
        {"v":"5.7.0","fr":60,"ip":0,"op":120,"w":512,"h":512,
         "assets":[{"id":"image_0","w":1,"h":1,"u":"","p":"x.png","e":0}],
         "layers":[{"ddd":0,"ind":1,"ty":2,"nm":"bitmap","refId":"image_0","sr":1,"ip":0,"op":120,"st":0,"bm":0,
           "ks":{"o":{"a":0,"k":100},"r":{"a":0,"k":0},"p":{"a":0,"k":[0,0,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}}}]}
        """
        #expect(!SendingLoaderAsset.isVectorOnly(Data(json.utf8)))
    }

    @Test func `an image asset alone, or an image layer alone, is not vector only`() {
        let asset = #"{"assets":[{"id":"i","w":1,"h":1,"u":"","p":"data:image/png;base64,AAAA","e":1}],"layers":[]}"#
        let layer = #"{"layers":[{"ty":2,"refId":"i"}]}"#
        let precompLayer = #"{"assets":[{"id":"c","layers":[{"ty":2,"refId":"i"}]}],"layers":[{"ty":0,"refId":"c"}]}"#
        let vector = #"{"assets":[{"id":"c","layers":[{"ty":4}]}],"layers":[{"ty":0,"refId":"c"},{"ty":4}]}"#
        #expect(!SendingLoaderAsset.isVectorOnly(Data(asset.utf8)))
        #expect(!SendingLoaderAsset.isVectorOnly(Data(layer.utf8)))
        #expect(!SendingLoaderAsset.isVectorOnly(Data(precompLayer.utf8)))
        #expect(SendingLoaderAsset.isVectorOnly(Data(vector.utf8)))
        #expect(!SendingLoaderAsset.isVectorOnly(Data("not json".utf8)))
    }

    @Test(arguments: [nil, Data(), Data("not lottie".utf8), Data(#"{"v":"5.7.0"}"#.utf8)])
    func `a missing or undecodable file gives no animation`(data: Data?) {
        #expect(SendingLoaderAsset.animation(from: data) == nil)
    }
}
