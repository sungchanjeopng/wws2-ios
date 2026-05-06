// Ported from app/src/main/java/com/wws2/densitymeter/model/ConnectedBleDevice.kt
//
// Note: Kotlin original holds an `android.bluetooth.BluetoothDevice?`. We omit it
// at the Core layer to keep WWS2Core platform-independent — the BLE layer
// (WWS2BLE) is responsible for mapping `id` ↔ `CBPeripheral`.
//
// `deviceType: Int` mirrors the firmware-level encoding (0=DENSITY, 1=INTERFACE)
// and is preserved as-is so wire formats remain identical to the Android port.

public struct ConnectedBleDevice: Equatable, Hashable, Identifiable, Codable, Sendable {
    public let id: String
    public let label: String
    /// "V0.1", "V1.1" 등
    public let firmwareVersion: String
    /// 0=DENSITY, 1=INTERFACE
    public let deviceType: Int

    public init(
        id: String,
        label: String,
        firmwareVersion: String = "",
        deviceType: Int = 0
    ) {
        self.id = id
        self.label = label
        self.firmwareVersion = firmwareVersion
        self.deviceType = deviceType
    }
}
