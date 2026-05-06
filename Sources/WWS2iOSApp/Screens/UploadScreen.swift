// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/UploadScreen.kt
//
// Four-state machine driven by AppViewModel:
//   firmwareTargetDeviceId.isEmpty  → SelectDeviceState
//   isUploading                     → UploadingState
//   uploadDone                      → CompleteState
//   else                            → ReadyState (file picker + start)

import SwiftUI
import WWS2Core

public struct UploadScreen: View {
    @ObservedObject var vm: AppViewModel
    public var onPickFile: () -> Void = {}

    public var body: some View {
        Group {
            if vm.state.firmwareTargetDeviceId.isEmpty {
                SelectDeviceState(vm: vm)
            } else if vm.state.isUploading {
                UploadingState(vm: vm)
            } else if vm.state.uploadDone {
                CompleteState(vm: vm)
            } else {
                ReadyState(vm: vm, onPickFile: onPickFile)
            }
        }
    }
}

private struct SelectDeviceState: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("SELECT DEVICE")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(0.3)
                    .foregroundStyle(AppColors.grayLabel)

                if vm.state.connectedDevices.isEmpty {
                    CardContainer {
                        Text("No connected devices available for firmware update.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.grayLabel)
                    }
                } else {
                    ForEach(vm.state.connectedDevices, id: \.id) { device in
                        HStack(spacing: 10) {
                            Circle().fill(AppColors.success).frame(width: 10, height: 10)
                            Text(device.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.darkText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(action: { vm.selectFirmwareTarget(device.id) }) {
                                Text("Update")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(AppColors.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(AppColors.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct ReadyState: View {
    @ObservedObject var vm: AppViewModel
    let onPickFile: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)
                ZStack {
                    Circle()
                        .fill(AppColors.primary.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.primary)
                }
                Spacer().frame(height: 16)
                Text("Firmware Update")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Spacer().frame(height: 6)
                Text("Select a firmware file to upload.")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.grayLabel)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 20)
                TargetCard(targetDevice: vm.firmwareTargetLabel ?? "--")
                Spacer().frame(height: 14)
                FileSelectArea(onTap: onPickFile)

                if let name = vm.state.pickedFileName {
                    Spacer().frame(height: 14)
                    SelectedFileCard(name: name, size: vm.state.pickedFileSize ?? 0)
                }

                Spacer().frame(height: 18)
                Button(action: { vm.startUpload() }) {
                    Text("Start Upload")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(vm.state.pickedFileName != nil ? AppColors.primary : AppColors.border)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(vm.state.pickedFileName == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct UploadingState: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.primary)
            }
            Spacer().frame(height: 20)
            Text("Uploading...")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppColors.darkText)
            Spacer().frame(height: 6)
            Text("Do not disconnect the device during firmware transfer.")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.grayLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Spacer().frame(height: 24)
            UploadProgressCard(
                fileName: vm.state.pickedFileName ?? "",
                fileSize: vm.state.pickedFileSize ?? 0,
                progress: vm.state.uploadProgress,
                isDone: false,
                elapsed: vm.state.uploadElapsed
            )
            .padding(.horizontal, 16)
            Spacer().frame(height: 14)
            TargetCard(targetDevice: vm.firmwareTargetLabel ?? "--")
                .padding(.horizontal, 16)

            Spacer().frame(height: 20)
            Button(action: { vm.cancelUpload() }) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColors.error, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Spacer()
        }
    }
}

private struct CompleteState: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)
                ZStack {
                    Circle()
                        .fill(AppColors.success.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.success)
                }
                Spacer().frame(height: 16)
                Text("Upload Complete")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                Spacer().frame(height: 6)
                Text("Firmware updated successfully.")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.grayLabel)

                Spacer().frame(height: 24)
                UploadProgressCard(
                    fileName: vm.state.pickedFileName ?? "",
                    fileSize: vm.state.pickedFileSize ?? 0,
                    progress: 1.0,
                    isDone: true,
                    elapsed: vm.state.uploadElapsed
                )
                Spacer().frame(height: 14)
                TargetCard(targetDevice: vm.firmwareTargetLabel ?? "--")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct TargetCard: View {
    let targetDevice: String
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Target Device")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.grayLabel)
                Text(targetDevice)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.darkText)
            }
        }
    }
}

private struct SelectedFileCard: View {
    let name: String
    let size: Int
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.background)
                    .frame(width: 42, height: 42)
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.darkText)
                    .lineLimit(1)
                Text("\(formatBytes(size)) / Selected")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.grayLabel)
            }
            Spacer()
        }
        .padding(16)
        .background(AppColors.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: AppColors.cardShadow, radius: 2, y: 1)
    }
}
