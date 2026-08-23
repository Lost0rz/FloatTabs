import AppKit

/// The one production seam for playing the ChatGPT Ready attention sound.
/// Both the automatic Ready alert and the Settings preview route through a
/// single player so sound choice, volume normalization, and the beep
/// fallback can never drift between call sites.
@MainActor
protocol AttentionSoundPlaying {
    func play(soundName: String, volume: Double)
}

@MainActor
final class AttentionSoundPlayer: AttentionSoundPlaying {
    typealias SystemPlayback = @MainActor (String, Float) -> Bool

    private let playSystemSound: SystemPlayback
    private let beep: () -> Void

    init(
        playSystemSound: @escaping SystemPlayback = AttentionSoundPlayer.playSystemSound,
        beep: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.playSystemSound = playSystemSound
        self.beep = beep
    }

    /// Plays `soundName` at `volume`. Any raw volume is normalized into the
    /// closed 0...1 range first. The beep fires only when the named system
    /// sound cannot load or start — an intentional zero volume is a valid
    /// silent configuration and must not fall back.
    func play(soundName: String, volume: Double) {
        let normalized = AppPreferencesStore.normalizedAttentionSoundVolume(volume)
        guard normalized > 0 else { return }
        if !playSystemSound(soundName, Float(normalized)) {
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
