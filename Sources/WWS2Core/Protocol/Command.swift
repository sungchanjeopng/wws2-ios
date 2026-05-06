// Ported from app/src/main/java/com/wws2/densitymeter/ble/protocol/Command.kt
//
// BLE protocol command constants. Matches firmware Comm_ProcBle() command IDs.

import Foundation

public enum Command {
    // Pairing / Device Info
    public static let cmdDeviceInfo: UInt16 = 0x00F0

    // Heartbeat / OTA
    public static let cmdOtaStart: UInt16 = 0x0050
    public static let cmdOtaEnd:   UInt16 = 0x0051

    // Density meter responses
    public static let cmdStatus: UInt16 = 0x0000
    public static let cmdEcho:   UInt16 = 0x0001
    public static let cmdTrend:  UInt16 = 0x0002
    public static let cmdCalib:  UInt16 = 0x0003
    public static let cmdDiag:   UInt16 = 0x0004

    // Interface meter responses (CH1)
    public static let cmdIfEchoReal: UInt16 = 0x0001
    public static let cmdIfEchoAvg:  UInt16 = 0x0005

    // Interface meter CH2 offsets
    public static let cmdStatusCh2:    UInt16 = 0x0010
    public static let cmdEchoCh2:      UInt16 = 0x0011
    public static let cmdTrendCh2:     UInt16 = 0x0012
    public static let cmdDiagCh2:      UInt16 = 0x0014
    public static let cmdIfEchoAvgCh2: UInt16 = 0x0015

    // Data download
    public static let cmdDownload:    UInt16 = 0x0007
    public static let cmdDownloadCh2: UInt16 = 0x0017

    // Data download cancel (app -> device request; device echoes same CMD as ack)
    public static let cmdDownloadCancel:    UInt16 = 0x0008
    public static let cmdDownloadCancelCh2: UInt16 = 0x0018

    // Stream end marker
    public static let cmdTrendEnd: UInt16 = 0x00FE

    // Heartbeat page indices (app -> device)
    public static let pageStatus:   UInt16 = 0x00
    public static let pageEcho:     UInt16 = 0x01
    public static let pageTrend:    UInt16 = 0x02
    public static let pageMenu:     UInt16 = 0x04
    public static let pagePairing:  UInt16 = 0x05
    public static let pageUpload:   UInt16 = 0x06
    public static let pageDownload: UInt16 = 0x07

    // CH2 page offsets
    public static let pageStatusCh2:   UInt16 = 0x10
    public static let pageEchoCh2:     UInt16 = 0x11
    public static let pageTrendCh2:    UInt16 = 0x12
    public static let pageEchoAvgCh2:  UInt16 = 0x15
    public static let pageDownloadCh2: UInt16 = 0x17

    // Device info lengths
    public static let lenDeviceInfoDensity:   UInt16 = 0x0005
    public static let lenDeviceInfoInterface: UInt16 = 0x0007
}
