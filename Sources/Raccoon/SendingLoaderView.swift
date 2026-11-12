import AppKit
import Lottie

/// The raccoon on the rocket, above the sending text (surfaces.md §7). It draws the mode it is
/// given and decides nothing: ResponseViewer says when, SendingLoaderMode says what.
final class SendingLoaderView: NSView {
    static let side = CGFloat(SendingLoaderMode.side)

    private let player: LottieAnimationView
    private(set) var mode = SendingLoaderMode.hidden
    /// Whether the loop is running now: `.play`, in a window that can be seen.
    private var isPlaying = false
    private var windowObservers: [NSObjectProtocol] = []

    /// Nil when there is no animation to show: the file is missing or does not decode.
    init?(data: Data?) {
        guard let animation = SendingLoaderAsset.animation(from: data) else { return nil }
        // Lottie's own Reduce Motion handling is off: the mode already decides it.
        player = LottieAnimationView(animation: animation, configuration: LottieConfiguration(reducedMotionOption: .standardMotion))
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        alphaValue = 0

        player.contentMode = .scaleAspectFit
        // Stays vector: never flattened to a bitmap while idle (Lottie's option, off by default).
        player.shouldRasterizeWhenIdle = false
        player.backgroundBehavior = .continuePlaying
        player.loopMode = .loop
        // Decorative: the status line's "Sending…" and the text say the state.
        for view in [self, player] { view.setAccessibilityElement(false) }

        // No background of its own: the animation is drawn straight on the Response pane.
        player.translatesAutoresizingMaskIntoConstraints = false
        addSubview(player)
        NSLayoutConstraint.activate([
            player.leadingAnchor.constraint(equalTo: leadingAnchor),
            player.trailingAnchor.constraint(equalTo: trailingAnchor),
            player.topAnchor.constraint(equalTo: topAnchor),
            player.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ new: SendingLoaderMode) {
        guard new != mode else { return }
        let old = mode
        mode = new
        switch new {
        case .hidden:
            syncPlayback()
            isHidden = true
            alphaValue = 0
        case .still:
            syncPlayback()
            player.currentFrame = SendingLoaderAsset.flyFrame
            isHidden = false
            alphaValue = 1
        case .play:
            isHidden = false
            if old == .hidden { fadeIn() } else { alphaValue = 1 }
            syncPlayback()
        }
    }

    /// 120 ms, ease-out, opacity only (surfaces.md §7).
    private func fadeIn() {
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            animator().alphaValue = 1
        }
    }

    /// A loop runs only in `.play` and in a window that can be seen; it starts from frame 0 each time.
    private func syncPlayback() {
        let shouldPlay = mode == .play && isWindowVisible
        guard shouldPlay != isPlaying else { return }
        isPlaying = shouldPlay
        if shouldPlay {
            player.play(fromProgress: 0, toProgress: 1, loopMode: .loop)
        } else {
            player.stop()
        }
    }

    private var isWindowVisible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !window.isMiniaturized
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        if let window {
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            ]
            windowObservers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.syncPlayback() }
                }
            }
        }
        syncPlayback()
    }
}
