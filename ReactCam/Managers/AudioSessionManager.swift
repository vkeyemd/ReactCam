import AVFoundation

enum AudioSessionManager {
    
    /// Configures the iOS audio routing to allow the camera microphone to record
    /// simultaneously while an AVPlayer is AirPlaying or Bluetooth-streaming to a TV.
    static func configureForReactCam() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // .mixWithOthers forces iOS not to kill our camera capture when playing the movie.
            // .allowBluetoothA2DP ensures high-quality routing (replaces the deprecated .allowBluetooth).
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .allowAirPlay,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker,
                    .mixWithOthers
                ]
            )
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    /// Forces the audio session to stay active while the camera is explicitly running
    static func activate() {
        configureForReactCam()
    }
    
    /// Configures routing for the playback-only screens -- the editor, whether it was reached
    /// from Projects or straight off a recording.
    ///
    /// Without this the Projects -> editor path never configures the session at all (nothing on
    /// it calls `activate()`), so the app sits in iOS's default `.soloAmbient` category, which
    /// the Ring/Silent switch mutes. That's why a saved project played silently through the
    /// speaker while headphones still worked: headphones masked a muted category, not a bad
    /// route. `.playback` is exempt from the silent switch and already prefers the speaker, so
    /// `.defaultToSpeaker` isn't needed here (it's only valid alongside `.playAndRecord`).
    static func configureForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Playback restarts on every loop, so don't rewrite the category when it's already
            // right. `setActive` still runs each time: after an interruption (a phone call) the
            // category survives but the session doesn't, and skipping it would leave playback
            // silent with no way back.
            if audioSession.category != .playback {
                try audioSession.setCategory(.playback, mode: .moviePlayback)
            }
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session for playback: \(error)")
        }
    }

    /// Safely deactivates the session to return audio control to the OS
    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    /// Whether audio is currently routing to headphones (wired or Bluetooth) rather than the
    /// built-in speaker. Used to decide whether it's safe to keep a reacted-to video's own audio
    /// track in the final export: without headphones, that audio plays out of the speaker and
    /// bleeds into the microphone recording already, so re-adding it separately would double it up.
    static var isUsingHeadphones: Bool {
        let headphoneLikePorts: Set<AVAudioSession.Port> = [
            .headphones,
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE
        ]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            headphoneLikePorts.contains($0.portType)
        }
    }
}
