import Foundation
import Lottie

/// The bundled raccoon-rocket.json and the one place it is parsed (surfaces.md §7). The file is
/// read-only art: nothing here edits it.
nonisolated enum SendingLoaderAsset {
    /// The Fly pose, 1.2 s into the 120-frame loop at 60 fps.
    static let flyFrame: AnimationFrameTime = 72

    static func bundledData() -> Data? {
        // try? is the escape: a missing file means no loader, and nobody is told (e-where-it-breaks.md).
        Bundle.module.url(forResource: "raccoon-rocket", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    /// True when the file embeds no image, so everything on screen is drawn from paths at the size it
    /// is shown at. A bitmap inside it would blur when scaled (design-system.md, Response viewer).
    /// Read from the JSON, because Lottie keeps its asset model internal: an image asset carries a
    /// path `p`, and an image layer has type 2.
    static func isVectorOnly(_ data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        let assets = root["assets"] as? [[String: Any]] ?? []
        let layers = (root["layers"] as? [[String: Any]] ?? []) + assets.flatMap { $0["layers"] as? [[String: Any]] ?? [] }
        return !assets.contains { $0["p"] != nil } && !layers.contains { $0["ty"] as? Int == 2 }
    }

    /// Nil for no data or data Lottie cannot decode: the same escape.
    static func animation(from data: Data?) -> LottieAnimation? {
        data.flatMap { try? LottieAnimation.from(data: $0) }
    }
}
