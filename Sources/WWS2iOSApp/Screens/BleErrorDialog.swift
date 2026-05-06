// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/BleErrorScreen.kt
//
// Compose used Material3 AlertDialog. SwiftUI's plain .alert(..) doesn't
// support custom headers/icons, so we build a presentation-modal-styled
// custom dialog. The shell wires this in via .sheet(...) or full-screen
// cover when a `BleErrorState` is set.

import SwiftUI

public struct BleErrorDialog: View {
    public let message: String
    public let onRetry: () -> Void
    public let onDismiss: () -> Void

    public init(message: String, onRetry: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppColors.error.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.error)
                }
                Text("Connection Failed")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                Button(action: onDismiss) {
                    Text("Go to Pairing")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.grayLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(AppColors.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)
        }
    }
}
