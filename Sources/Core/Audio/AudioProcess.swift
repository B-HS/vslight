import CoreAudio
import Foundation

struct AudioProcess: Identifiable, Hashable {
    let id: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let name: String
}
