// Ported from app/src/main/java/com/wws2/densitymeter/ble/protocol/Crc.kt
//
// CRC algorithms used by the BLE protocol. Pure functions, no state.

import Foundation

public enum Crc {

    /// CRC-16 Modbus (polynomial 0xA001).
    public static func crc16Modbus(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in data {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    /// Incremental CRC-16 update for a single byte.
    public static func crc16Update(_ crc: UInt16, _ b: UInt8) -> UInt16 {
        var c = crc ^ UInt16(b)
        for _ in 0..<8 {
            if (c & 0x0001) != 0 {
                c = (c >> 1) ^ 0xA001
            } else {
                c >>= 1
            }
        }
        return c
    }

    /// CRC-32 (polynomial 0xEDB88320, same as firmware BspMram_Crc32).
    public static func crc32(_ data: [UInt8]) -> UInt32 {
        let poly: UInt32 = 0xEDB88320
        let table: [UInt32] = (0..<256).map { i in
            var c: UInt32 = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = poly ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            return c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            let idx = Int((crc ^ UInt32(b)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
