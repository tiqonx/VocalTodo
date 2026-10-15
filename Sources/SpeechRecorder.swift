import Speech
import AVFoundation

@MainActor
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?
    var onFinished: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var delivered = false

    func toggle() {
        if isRecording { stop() } else { Task { await start() } }
    }

    private func start() async {
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            errorMessage = "Autorise le micro et la reconnaissance vocale dans Réglages."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Reconnaissance vocale indisponible pour le moment."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()

            transcript = ""
            delivered = false
            errorMessage = nil
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if (result?.isFinal ?? false) || error != nil { self.finish() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio() // déclenche le résultat final
    }

    private func finish() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isRecording = false
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !delivered, !transcript.isEmpty {
            delivered = true
            onFinished?(transcript)
        }
    }
}
