import Foundation
import AVFoundation
import UIKit

enum AlarmSound: String, CaseIterable, Identifiable {
    case radar = "Radar"
    case beacon = "Beacon"
    case pulse = "Pulse"
    case chime = "Chime"
    case alert = "Alert"
    case system = "Default"

    var id: String { rawValue }

    var filename: String {
        switch self {
        case .system: return ""
        default: return "alarm_\(rawValue.lowercased()).caf"
        }
    }

    var frequency: Double {
        switch self {
        case .radar: return 880
        case .beacon: return 1047
        case .pulse: return 660
        case .chime: return 1320
        case .alert: return 740
        case .system: return 0
        }
    }

    var pattern: SoundPattern {
        switch self {
        case .radar: return .rapid
        case .beacon: return .slowPulse
        case .pulse: return .heartbeat
        case .chime: return .ascending
        case .alert: return .urgent
        case .system: return .rapid
        }
    }

    enum SoundPattern {
        case rapid, slowPulse, heartbeat, ascending, urgent
    }
}

final class AlarmSoundManager {
    static let shared = AlarmSoundManager()

    private let soundsDirectory: URL
    private var previewPlayer: AVAudioPlayer?

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        soundsDirectory = library.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
    }

    var selectedSound: AlarmSound {
        get {
            let raw = UserDefaults.standard.string(forKey: "selectedAlarmSound") ?? AlarmSound.radar.rawValue
            return AlarmSound(rawValue: raw) ?? .radar
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedAlarmSound")
        }
    }

    func generateAllSounds() {
        for sound in AlarmSound.allCases where sound != .system {
            let url = soundsDirectory.appendingPathComponent(sound.filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                generateSound(sound, to: url)
            }
        }
    }

    func notificationSound() -> UNNotificationSound {
        let sound = selectedSound
        if sound == .system {
            return .default
        }
        return UNNotificationSound(named: UNNotificationSoundName(sound.filename))
    }

    func previewSound(_ sound: AlarmSound) {
        stopPreview()

        if sound == .system {
            AudioServicesPlayAlertSound(SystemSoundID(1007))
            triggerHaptic()
            return
        }

        let url = soundsDirectory.appendingPathComponent(sound.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.volume = 1.0
            previewPlayer?.play()
            triggerHaptic()
        } catch {}
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    func triggerHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
    }

    // MARK: - Sound Generation

    private func generateSound(_ sound: AlarmSound, to url: URL) {
        let sampleRate: Double = 44100
        let duration: Double = 3.0
        let totalSamples = Int(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(totalSamples)
        guard let data = buffer.floatChannelData?[0] else { return }

        switch sound.pattern {
        case .rapid:
            generateRapidBeeps(data: data, samples: totalSamples, sampleRate: sampleRate, freq: sound.frequency)
        case .slowPulse:
            generateSlowPulse(data: data, samples: totalSamples, sampleRate: sampleRate, freq: sound.frequency)
        case .heartbeat:
            generateHeartbeat(data: data, samples: totalSamples, sampleRate: sampleRate, freq: sound.frequency)
        case .ascending:
            generateAscending(data: data, samples: totalSamples, sampleRate: sampleRate, freq: sound.frequency)
        case .urgent:
            generateUrgent(data: data, samples: totalSamples, sampleRate: sampleRate, freq: sound.frequency)
        }

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        } catch {}
    }

    private func generateRapidBeeps(data: UnsafeMutablePointer<Float>, samples: Int, sampleRate: Double, freq: Double) {
        let beepDuration = 0.12
        let gapDuration = 0.08
        let cycleDuration = beepDuration + gapDuration

        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let phase = t.truncatingRemainder(dividingBy: cycleDuration)
            if phase < beepDuration {
                let envelope = min(phase / 0.005, (beepDuration - phase) / 0.005, 1.0)
                data[i] = Float(sin(2.0 * .pi * freq * t) * 0.7 * envelope)
            } else {
                data[i] = 0
            }
        }
    }

    private func generateSlowPulse(data: UnsafeMutablePointer<Float>, samples: Int, sampleRate: Double, freq: Double) {
        let beepDuration = 0.5
        let gapDuration = 0.5
        let cycleDuration = beepDuration + gapDuration

        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let phase = t.truncatingRemainder(dividingBy: cycleDuration)
            if phase < beepDuration {
                let fadeIn = min(phase / 0.05, 1.0)
                let fadeOut = min((beepDuration - phase) / 0.05, 1.0)
                data[i] = Float(sin(2.0 * .pi * freq * t) * 0.6 * fadeIn * fadeOut)
            } else {
                data[i] = 0
            }
        }
    }

    private func generateHeartbeat(data: UnsafeMutablePointer<Float>, samples: Int, sampleRate: Double, freq: Double) {
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let cyclePos = t.truncatingRemainder(dividingBy: 1.0)

            var amplitude: Double = 0
            if cyclePos < 0.08 {
                amplitude = sin(cyclePos / 0.08 * .pi) * 0.8
            } else if cyclePos > 0.15 && cyclePos < 0.23 {
                amplitude = sin((cyclePos - 0.15) / 0.08 * .pi) * 0.5
            }

            data[i] = Float(sin(2.0 * .pi * freq * t) * amplitude)
        }
    }

    private func generateAscending(data: UnsafeMutablePointer<Float>, samples: Int, sampleRate: Double, freq: Double) {
        let noteDuration = 0.2
        let noteCount = 4
        let groupDuration = noteDuration * Double(noteCount) + 0.4

        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let groupPhase = t.truncatingRemainder(dividingBy: groupDuration)

            let noteIndex = Int(groupPhase / noteDuration)
            if noteIndex < noteCount {
                let notePhase = groupPhase.truncatingRemainder(dividingBy: noteDuration)
                let noteFreq = freq * pow(1.2, Double(noteIndex))
                let envelope = min(notePhase / 0.01, (noteDuration - notePhase) / 0.01, 1.0)
                data[i] = Float(sin(2.0 * .pi * noteFreq * t) * 0.6 * envelope)
            } else {
                data[i] = 0
            }
        }
    }

    private func generateUrgent(data: UnsafeMutablePointer<Float>, samples: Int, sampleRate: Double, freq: Double) {
        let onDuration = 0.15
        let offDuration = 0.05
        let cycleDuration = onDuration + offDuration

        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let phase = t.truncatingRemainder(dividingBy: cycleDuration)
            if phase < onDuration {
                let wobble = freq + sin(t * 30) * 50
                let envelope = min(phase / 0.003, (onDuration - phase) / 0.003, 1.0)
                data[i] = Float(sin(2.0 * .pi * wobble * t) * 0.75 * envelope)
            } else {
                data[i] = 0
            }
        }
    }
}
