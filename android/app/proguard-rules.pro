# PlaybackServiceControl releases audio_service's wake lock by this field's name
-keepclassmembers class com.ryanheise.audioservice.AudioService {
    private android.os.PowerManager$WakeLock wakeLock;
    # BrowseGuard wraps the plugin's listener by this field's name
    private static com.ryanheise.audioservice.AudioService$ServiceListener listener;
}
