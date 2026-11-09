# PlaybackServiceControl releases audio_service's wake lock by this field's name
-keepclassmembers class com.ryanheise.audioservice.AudioService {
    private android.os.PowerManager$WakeLock wakeLock;
}
