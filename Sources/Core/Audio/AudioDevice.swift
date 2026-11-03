import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable, Sendable {
    enum Transport: Sendable {
        case builtIn
        case usb
        case bluetooth
        case bluetoothLE
        case hdmi
        case displayPort
        case airPlay
        case virtual
        case aggregate
        case thunderbolt
        case pci
        case fireWire
        case avb
        case other

        var label: String {
            switch self {
            case .builtIn: String(localized: "내장")
            case .usb: String(localized: "USB")
            case .bluetooth: String(localized: "Bluetooth")
            case .bluetoothLE: String(localized: "Bluetooth LE")
            case .hdmi: String(localized: "HDMI")
            case .displayPort: String(localized: "DisplayPort")
            case .airPlay: String(localized: "AirPlay")
            case .virtual: String(localized: "가상")
            case .aggregate: String(localized: "집계 장치")
            case .thunderbolt: String(localized: "Thunderbolt")
            case .pci: String(localized: "PCI")
            case .fireWire: String(localized: "FireWire")
            case .avb: String(localized: "AVB")
            case .other: String(localized: "기타")
            }
        }

        var symbolName: String {
            switch self {
            case .builtIn: "laptopcomputer"
            case .usb: "cable.connector"
            case .bluetooth, .bluetoothLE: "wave.3.right"
            case .hdmi, .displayPort: "display"
            case .airPlay: "airplayaudio"
            case .virtual, .aggregate: "square.stack.3d.up"
            case .thunderbolt: "bolt.horizontal"
            case .pci: "cpu"
            case .fireWire: "flame"
            case .avb: "network"
            case .other: "hifispeaker"
            }
        }

        static func from(_ rawValue: UInt32) -> Transport {
            switch rawValue {
            case kAudioDeviceTransportTypeBuiltIn: .builtIn
            case kAudioDeviceTransportTypeUSB: .usb
            case kAudioDeviceTransportTypeBluetooth: .bluetooth
            case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
            case kAudioDeviceTransportTypeHDMI: .hdmi
            case kAudioDeviceTransportTypeDisplayPort: .displayPort
            case kAudioDeviceTransportTypeAirPlay: .airPlay
            case kAudioDeviceTransportTypeVirtual: .virtual
            case kAudioDeviceTransportTypeAggregate: .aggregate
            case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
            case kAudioDeviceTransportTypePCI: .pci
            case kAudioDeviceTransportTypeFireWire: .fireWire
            case kAudioDeviceTransportTypeAVB: .avb
            default: .other
            }
        }
    }

    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: Transport
    let outputChannels: Int

    static func defaultOutputID() -> AudioObjectID? {
        var address = audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var id: AudioObjectID = kAudioObjectUnknown
        let status = AudioObjectGetPropertyData(systemAudioObject, &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else {
            return nil
        }
        return id
    }

    static func allOutputDevices() -> [AudioDevice] {
        let address = audioPropertyAddress(kAudioHardwarePropertyDevices)
        guard let ids = try? AudioProperty.getArray(systemAudioObject, address) else {
            return []
        }
        return ids.compactMap(device(id:)).sorted { left, right in
            left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    static func device(id: AudioObjectID) -> AudioDevice? {
        let channels = AudioProperty.outputChannelCount(id)
        let canBeDefaultAddress = audioPropertyAddress(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput)
        let canBeDefault: UInt32 = (try? AudioProperty.get(id, canBeDefaultAddress, defaultValue: 0)) ?? 0
        guard channels > 0 || canBeDefault != 0 else {
            return nil
        }
        let uid = (try? AudioProperty.getString(id, audioPropertyAddress(kAudioDevicePropertyDeviceUID))) ?? "device-\(id)"
        let rawName = try? AudioProperty.getString(id, audioPropertyAddress(kAudioObjectPropertyName))
        let name = (rawName?.isEmpty == false ? rawName : nil) ?? uid
        let transportRaw: UInt32 = (try? AudioProperty.get(id, audioPropertyAddress(kAudioDevicePropertyTransportType), defaultValue: 0)) ?? 0
        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            transport: Transport.from(transportRaw),
            outputChannels: channels
        )
    }
}
