package com.nocturne.enginehook;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Hands every Flutter engine to the app, the moment it is made and before any Dart runs.
 *
 * The app used to set its channels up in MainActivity. When audio_service started the engine
 * with no window (a Bluetooth play button after the app was closed), the activity never came,
 * so library scan, song analysis and pocket knock found no channel. A plugin is attached to
 * every engine, with a window or without one.
 */
public final class EngineHookPlugin implements FlutterPlugin {
    public interface Listener {
        void onAttached(FlutterPluginBinding binding);

        void onDetached(FlutterPluginBinding binding);
    }

    private static Listener listener;

    /** Set once, in Application.onCreate: that runs before any engine is made. */
    public static void setListener(Listener l) {
        listener = l;
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        if (listener != null) listener.onAttached(binding);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (listener != null) listener.onDetached(binding);
    }
}
