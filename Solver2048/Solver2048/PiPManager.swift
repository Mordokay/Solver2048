import AVKit
import UIKit
import SwiftUI

/// Displays the solver's recommended direction in a Picture-in-Picture floating window.
/// The window floats over other apps and can be dragged around, just like YouTube's PiP player.

// MARK: - Arrow View Controller (content shown inside PiP)

class ArrowViewController: AVPictureInPictureVideoCallViewController {
    private let arrowImageView = UIImageView()
    private let padding: CGFloat = 12

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.1, green: 0.07, blue: 0.05, alpha: 0.95)

        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.tintColor = .systemOrange
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arrowImageView)

        NSLayoutConstraint.activate([
            arrowImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            arrowImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            arrowImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            arrowImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
        ])

        preferredContentSize = CGSize(width: 150, height: 150)
        updateDirection("---")
    }

    func updateDirection(_ direction: String) {
        let iconName: String
        switch direction {
        case "UP":    iconName = "arrow.up"
        case "DOWN":  iconName = "arrow.down"
        case "LEFT":  iconName = "arrow.left"
        case "RIGHT": iconName = "arrow.right"
        default:      iconName = "questionmark"
        }

        let config = UIImage.SymbolConfiguration(pointSize: 200, weight: .bold)
        arrowImageView.image = UIImage(systemName: iconName, withConfiguration: config)

        // Flash animation on change
        arrowImageView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.arrowImageView.transform = .identity
        }
    }
}

// MARK: - PiP Source View (UIViewRepresentable for SwiftUI embedding)

/// Embeds a UIKit view in SwiftUI that serves as the PiP source.
/// When the app goes to background, this view "shrinks" into the floating PiP window.
struct PiPSourceView: UIViewRepresentable {
    let pipManager: PiPManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // Setup PiP once the view is in the hierarchy
        DispatchQueue.main.async {
            pipManager.setup(sourceView: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - PiP Manager

@MainActor
final class PiPManager: NSObject, @preconcurrency AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    private let arrowVC = ArrowViewController()

    private(set) var isPiPActive: Bool = false

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func setup(sourceView: UIView) {
        guard Self.isSupported else {
            print("[PiP] PiP is not supported on this device")
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: arrowVC
        )

        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        pipController?.delegate = self
        print("[PiP] Setup complete")
    }

    func start() {
        guard let pip = pipController, !pip.isPictureInPictureActive else { return }
        pip.startPictureInPicture()
    }

    func stop() {
        guard let pip = pipController, pip.isPictureInPictureActive else { return }
        pip.stopPictureInPicture()
    }

    func updateDirection(_ direction: String) {
        arrowVC.updateDirection(direction)
    }

    // MARK: - AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
        }
        print("[PiP] Will start")
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
        }
        print("[PiP] Did stop")
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("[PiP] Failed to start: \(error)")
    }
}
