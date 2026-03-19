import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognitionService: ObservableObject {
    static let shared = SpeechRecognitionService()

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var isAuthorized = false

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 2.5

    var onAutoStop: (() -> Void)?

    private init() {}

    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let authorized = speechGranted && micGranted
        self.isAuthorized = authorized
        return authorized
    }

    func startRecording() throws {
        stopRecording()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }

                if let error {
                    let nsError = error as NSError
                    let isCancellation = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
                    let isInterrupted = nsError.code == 1110
                    if !isCancellation && !isInterrupted {
                        self.stopRecording()
                    }
                }

                if result?.isFinal == true {
                    self.stopRecording()
                    self.onAutoStop?()
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
        isRecording = true
        transcribedText = ""

        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        guard isRecording else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, !self.transcribedText.isEmpty else { return }
                self.stopRecording()
                self.onAutoStop?()
            }
        }
    }

    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    func resetTranscription() {
        transcribedText = ""
    }
}
