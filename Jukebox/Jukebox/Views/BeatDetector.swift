//
//  BeatDetector.swift
//  Jukebox
//
//  real-time beat detection using audio analysis.
//  uses the device microphone to detect beats from any audio source.
//

import AVFoundation
import Accelerate
import Combine

class BeatDetector: ObservableObject {
    static let shared = BeatDetector()
    
    // published values for ui binding
    @Published var beatIntensity: CGFloat = 0.0
    @Published var isBeat: Bool = false
    @Published var lowFrequencyEnergy: CGFloat = 0.0
    @Published var midFrequencyEnergy: CGFloat = 0.0
    @Published var highFrequencyEnergy: CGFloat = 0.0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // beat detection parameters
    private var energyHistory: [Float] = []
    private let historySize = 43 // ~1 second of history at 43 fps
    private var lastBeatTime: Date = Date()
    private let minBeatInterval: TimeInterval = 0.15 // minimum time between beats
    
    // fft setup
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize = 1024
    
    private var isRunning = false
    
    init() {
        setupFFT()
    }
    
    private func setupFFT() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }
    
    func start() {
        guard !isRunning else { return }
        
        // request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else {
                print("microphone permission denied")
                return
            }
            
            DispatchQueue.main.async {
                self?.setupAudioEngine()
            }
        }
    }
    
    func stop() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        isRunning = false
    }
    
    private func setupAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }
            
            inputNode = engine.inputNode
            let format = inputNode?.outputFormat(forBus: 0)
            
            guard let audioFormat = format, audioFormat.sampleRate > 0 else {
                print("invalid audio format")
                return
            }
            
            // install tap on input to analyze audio
            inputNode?.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: audioFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer)
            }
            
            try engine.start()
            isRunning = true
            
        } catch {
            print("failed to setup audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frames = buffer.frameLength
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(frames)))
        
        // perform fft analysis
        analyzeFrequencies(samples)
        
        // calculate overall energy
        var energy: Float = 0
        vDSP_measqv(samples, 1, &energy, vDSP_Length(samples.count))
        energy = sqrt(energy)
        
        // update energy history
        energyHistory.append(energy)
        if energyHistory.count > historySize {
            energyHistory.removeFirst()
        }
        
        // detect beat using energy threshold
        let avgEnergy = energyHistory.reduce(0, +) / Float(max(1, energyHistory.count))
        let threshold = avgEnergy * 1.5
        
        let now = Date()
        let timeSinceLastBeat = now.timeIntervalSince(lastBeatTime)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // smooth intensity decay
            let targetIntensity = CGFloat(min(1.0, energy / max(0.001, avgEnergy * 2)))
            self.beatIntensity = self.beatIntensity * 0.7 + targetIntensity * 0.3
            
            // detect beat
            if energy > threshold && timeSinceLastBeat > self.minBeatInterval {
                self.isBeat = true
                self.lastBeatTime = now
                
                // quick decay for beat indicator
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isBeat = false
                }
            }
        }
    }
    
    private func analyzeFrequencies(_ samples: [Float]) {
        guard samples.count >= fftSize else { return }
        
        // prepare input for fft
        var realInput = [Float](samples.prefix(fftSize))
        var imagInput = [Float](repeating: 0, count: fftSize)
        var realOutput = [Float](repeating: 0, count: fftSize)
        var imagOutput = [Float](repeating: 0, count: fftSize)
        
        guard let setup = fftSetup else { return }
        
        vDSP_DFT_Execute(setup, &realInput, &imagInput, &realOutput, &imagOutput)
        
        // calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<fftSize/2 {
            magnitudes[i] = sqrt(realOutput[i] * realOutput[i] + imagOutput[i] * imagOutput[i])
        }
        
        // split into frequency bands
        let lowEnd = fftSize / 16   // bass frequencies
        let midEnd = fftSize / 4    // mid frequencies
        
        var lowSum: Float = 0
        var midSum: Float = 0
        var highSum: Float = 0
        
        for i in 0..<lowEnd {
            lowSum += magnitudes[i]
        }
        for i in lowEnd..<midEnd {
            midSum += magnitudes[i]
        }
        for i in midEnd..<fftSize/2 {
            highSum += magnitudes[i]
        }
        
        let lowAvg = lowSum / Float(lowEnd)
        let midAvg = midSum / Float(midEnd - lowEnd)
        let highAvg = highSum / Float(fftSize/2 - midEnd)
        
        let maxVal = max(lowAvg, max(midAvg, highAvg), 0.001)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // smooth frequency energy values
            self.lowFrequencyEnergy = self.lowFrequencyEnergy * 0.8 + CGFloat(lowAvg / maxVal) * 0.2
            self.midFrequencyEnergy = self.midFrequencyEnergy * 0.8 + CGFloat(midAvg / maxVal) * 0.2
            self.highFrequencyEnergy = self.highFrequencyEnergy * 0.8 + CGFloat(highAvg / maxVal) * 0.2
        }
    }
    
    deinit {
        stop()
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
}
