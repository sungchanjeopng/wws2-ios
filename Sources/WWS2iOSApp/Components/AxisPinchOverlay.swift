import SwiftUI
import UIKit

/// Transparent UIKit bridge for Android-like axis-specific two-finger zoom.
/// - Horizontal finger spread changes only X zoom.
/// - Vertical finger spread changes only Y zoom.
///
/// The recognizer is attached to the SwiftUI host/superview instead of this
/// transparent overlay view so one-finger SwiftUI drag/crosshair gestures still work.
struct AxisPinchOverlay: UIViewRepresentable {
    let onChanged: (_ scaleXDelta: CGFloat, _ scaleYDelta: CGFloat, _ center: CGPoint) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> AttachView {
        let view = AttachView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AttachView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        uiView.coordinator = context.coordinator
        uiView.attachIfNeeded()
    }

    final class AttachView: UIView {
        weak var coordinator: Coordinator?
        private weak var attachedToView: UIView?
        private weak var recognizer: UIPinchGestureRecognizer?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            guard let superview, let coordinator else { return }
            if attachedToView === superview, recognizer != nil { return }
            if let recognizer, let attachedToView {
                attachedToView.removeGestureRecognizer(recognizer)
            }
            let newRecognizer = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
            newRecognizer.delegate = coordinator
            newRecognizer.cancelsTouchesInView = false
            newRecognizer.delaysTouchesBegan = false
            newRecognizer.delaysTouchesEnded = false
            superview.addGestureRecognizer(newRecognizer)
            attachedToView = superview
            recognizer = newRecognizer
        }

        deinit {
            if let recognizer, let attachedToView {
                attachedToView.removeGestureRecognizer(recognizer)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (_ scaleXDelta: CGFloat, _ scaleYDelta: CGFloat, _ center: CGPoint) -> Void
        var onEnded: () -> Void
        private var lastHorizontalDistance: CGFloat?
        private var lastVerticalDistance: CGFloat?

        init(
            onChanged: @escaping (_ scaleXDelta: CGFloat, _ scaleYDelta: CGFloat, _ center: CGPoint) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view, recognizer.numberOfTouches >= 2 else {
                reset()
                onEnded()
                return
            }

            let p0 = recognizer.location(ofTouch: 0, in: view)
            let p1 = recognizer.location(ofTouch: 1, in: view)
            let horizontalDistance = max(abs(p1.x - p0.x), 1)
            let verticalDistance = max(abs(p1.y - p0.y), 1)
            let center = recognizer.location(in: view)

            switch recognizer.state {
            case .began:
                lastHorizontalDistance = horizontalDistance
                lastVerticalDistance = verticalDistance
            case .changed:
                guard let lastH = lastHorizontalDistance, let lastV = lastVerticalDistance else {
                    lastHorizontalDistance = horizontalDistance
                    lastVerticalDistance = verticalDistance
                    return
                }

                let horizontalChange = abs(horizontalDistance - lastH)
                let verticalChange = abs(verticalDistance - lastV)

                if horizontalChange >= verticalChange {
                    onChanged(horizontalDistance / max(lastH, 1), 1, center)
                } else {
                    onChanged(1, verticalDistance / max(lastV, 1), center)
                }

                lastHorizontalDistance = horizontalDistance
                lastVerticalDistance = verticalDistance
            case .ended, .cancelled, .failed:
                reset()
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func reset() {
            lastHorizontalDistance = nil
            lastVerticalDistance = nil
        }
    }
}
