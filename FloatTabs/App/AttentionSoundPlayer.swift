import AppKit

/// The one production seam for playing the ChatGPT Ready attention sound.
/// Both the automatic Ready alert and the Settings preview route through a
/// single player so sound choice, volume normalization, and the beep/fallback
/// behavior can never drift between call sites.
@MainActor
protocol AttentionSoundPlaying {
    func play(source: AttentionSoundPlaybackSource, volume: Double)
}

@MainActor
extension AttentionSoundPlaying {
    func play(soundName: String, volume: Double) {
        play(source: .system(name: soundName), volume: volume)
    }
}

@MainActor
final class AttentionSoundPlayer: AttentionSoundPlaying {
    typealias SystemPlayback = @MainActor (String, Float) -> Bool
    typealias CustomSoundLoader = @MainActor (URL) -> NSSound?
    typealias CustomPlayback = @MainActor (NSSound, Float) -> Bool

    private let playSystemSound: SystemPlayback
    private let loadCustomSound: CustomSoundLoader
    private let playCustomSound: CustomPlayback
    private let beep: () -> Void
    private(set) var activeSound: NSSound?

    init(
        playSystemSound: @escaping SystemPlayback = AttentionSoundPlayer.playSystemSound,
        loadCustomSound: @escaping CustomSoundLoader = AttentionSoundPlayer.loadCustomSound,
        playCustomSound: @escaping CustomPlayback = AttentionSoundPlayer.playCustomSound,
        beep: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.playSystemSound = playSystemSound
        self.loadCustomSound = loadCustomSound
        self.playCustomSound = playCustomSound
        self.beep = beep
    }

    /// Plays a typed system or managed custom source at `volume`. Any raw
    /// volume is normalized into the closed 0...1 range first. A custom source
    /// that cannot load or start falls back to Ping and then beep. A missing
    /// system sound keeps the existing direct-beep behavior. Zero stays silent.
    func play(source: AttentionSoundPlaybackSource, volume: Double) {
        let normalized = AppPreferencesStore.normalizedAttentionSoundVolume(volume)
        activeSound?.stop()
        activeSound = nil
        guard normalized > 0 else { return }

        let volume = Float(normalized)
        switch source {
        case let .system(name):
            if !playSystemSound(name, volume) {
                // Preserve the existing system-sound behavior: an invalid
                // configured macOS name falls straight to the platform beep.
                beep()
            }
        case let .custom(url):
            guard let sound = loadCustomSound(url),
                  playCustomSound(sound, volume) else {
                playFallback(volume: volume)
                return
            }
            // NSSound must stay alive for the duration of asynchronous
            // playback. The next preview/Ready sound replaces this handle.
            activeSound = sound
        }
    }

    private func playFallback(volume: Float) {
        if !playSystemSound(AppPreferencesStore.defaultAttentionSoundName, volume) {
            beep()
        }
    }

    /// The exact production order — load, set volume, play — so a failure at
    /// any step means the alert was not heard and the caller beeps instead.
    private static func playSystemSound(name: String, volume: Float) -> Bool {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return false
        }
        sound.volume = volume
        return sound.play()
    }

    private static func loadCustomSound(url: URL) -> NSSound? {
        NSSound(contentsOf: url, byReference: false)
    }

    private static func playCustomSound(sound: NSSound, volume: Float) -> Bool {
        sound.volume = volume
        return sound.play()
    }
}

/// Curated ChatGPT Ready alert sound candidates drawn from macOS system
/// sounds. Only names that actually load through `NSSound(named:)` on the
/// current system are offered in Settings; `ping` stays first so the
/// default candidate keeps priority even when filtering.
@MainActor
enum AttentionSound: String, CaseIterable {
    case ping = "Ping"
    case glass = "Glass"
    case pop = "Pop"
    case purr = "Purr"
    case tink = "Tink"

    static func availableNames(
        isLoadable: (String) -> Bool = { NSSound(named: NSSound.Name($0)) != nil }
    ) -> [String] {
        allCases.map(\.rawValue).filter(isLoadable)
    }
}
