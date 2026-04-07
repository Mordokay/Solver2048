import SwiftUI
import ReplayKit

/// UIViewRepresentable wrapper for RPSystemBroadcastPickerView.
/// Shows the system broadcast picker button that starts screen capture.
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        picker.preferredExtension = SharedState.extensionBundleID
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear

        // Style the internal button to be visible
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.imageView?.tintColor = .white
                button.tintColor = .white
                // Make button fill the picker
                button.frame = picker.bounds
                button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }

        print("[BroadcastPicker] Created with preferredExtension: \(SharedState.extensionBundleID)")
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
