import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognitionService: ObservableObject {
    static let shared = SpeechRecognitionService()

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// Fires after this many seconds of silence to auto-stop recording
    private let silenceTimeout: TimeInterval = 1.5
    private var silenceTimer: Timer?

    private init() {}

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.isAuthorized = (status == .authorized)
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func startRecording() throws {
        cleanupAudioEngine()
        cleanupTask()
        cancelSilenceTimer()
        errorMessage = nil

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available."
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Do NOT force on-device recognition — server-side is more reliable at
        // detecting end-of-speech and marking results as final.

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    // New speech came in — reset the silence countdown
                    self.resetSilenceTimer()
                }

                let isCancellation = (error as? NSError).map {
                    $0.code == 301 || $0.code == 203
                } ?? false

                if result?.isFinal == true {
                    self.cancelSilenceTimer()
                    self.recognitionTask = nil
                    self.isRecording = false
                } else if let error, !isCancellation {
                    self.cancelSilenceTimer()
                    self.errorMessage = error.localizedDescription
                    self.recognitionTask = nil
                    self.isRecording = false
                } else if error != nil && isCancellation {
                    self.cancelSilenceTimer()
                    self.recognitionTask = nil
                    self.isRecording = false
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
        transcribedText = ""
        isRecording = true

        // Start the initial silence timer — if the user never speaks, stop after timeout
        resetSilenceTimer()
    }

    func stopRecording() {
        cancelSilenceTimer()
        cleanupAudioEngine()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if recognitionTask == nil {
            isRecording = false
        }
    }

    func resetTranscription() {
        transcribedText = ""
        errorMessage = nil
    }

    // MARK: - Silence detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording()
            }
        }
    }

    private func cancelSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Private helpers

    private func cleanupAudioEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func cleanupTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
