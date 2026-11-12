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

    /// Nil for no data or data Lottie cannot decode: the same escape.
    static func animation(from data: Data?) -> LottieAnimation? {
        data.flatMap { try? LottieAnimation.from(data: $0) }
    }
}
