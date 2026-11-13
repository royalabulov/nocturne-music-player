package com.nocturne

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.os.PowerManager
import android.support.v4.media.session.PlaybackStateCompat
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import com.ryanheise.audioservice.PlaybackServiceControl
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// The home screen widgets: small (2×2), wide (4×1) and large (4×2). Each shows what the app
/// last sent (HomeWidgetSync in Dart), kept in a small preferences file so a widget added
/// later, or redrawn after a reboot or an update, still shows the last song.
///
/// Play/pause, previous and next go to audio_service's MediaButtonReceiver exactly like a
/// headset button, so they work with the app closed too (play brings the last queue back).
/// Shuffle, repeat and favorite need the app's own code and go to Dart (WidgetActionReceiver).
class NowPlayingSmallWidget : NowPlayingWidget(WidgetKind.SMALL)

class NowPlayingWideWidget : NowPlayingWidget(WidgetKind.WIDE)

class NowPlayingLargeWidget : NowPlayingWidget(WidgetKind.LARGE)

abstract class NowPlayingWidget(private val kind: WidgetKind) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        HomeWidgets.render(context, manager, kind, ids)

    /// Resized: the small widget's cover is cut to the new shape.
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        HomeWidgets.render(context, manager, kind, intArrayOf(id))
}

enum class WidgetKind(val layout: Int) {
    SMALL(R.layout.widget_small),
    WIDE(R.layout.widget_wide),
    LARGE(R.layout.widget_large);

    fun provider(context: Context) = ComponentName(
        context,
        when (this) {
            SMALL -> NowPlayingSmallWidget::class.java
            WIDE -> NowPlayingWideWidget::class.java
            LARGE -> NowPlayingLargeWidget::class.java
        },
    )
}

/// Shuffle, repeat and favorite pressed on a widget → the app (Dart). With the app's engine
/// gone there is nobody to do it; the widget's song then can't change anyway.
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val name = intent.action?.removePrefix(ACTION_PREFIX) ?: return
        if (name in ACTIONS) EngineChannels.current?.widgetAction(name)
    }

    companion object {
        const val ACTION_PREFIX = "com.nocturne.widget."
        val ACTIONS = setOf("shuffle", "repeat", "favorite")
    }
}

/// What a widget shows, as HomeWidgetSync sends it (JSON, also how it is kept).
data class WidgetState(
    val hasTrack: Boolean,
    val title: String,
    val artist: String,
    val cover: String?,
    /// Track id: picks the placeholder's hue, as AlbumArt does.
    val seed: Int,
    val playing: Boolean,
    val shuffle: Boolean,
    /// "none", "all" or "one".
    val repeat: String,
    val favorite: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    /// The body colour: the glass with the cover's colour washed over it (opaque RGB).
    val tint: Int,
    /// Spoken names of the buttons, in the app's language.
    val labels: Map<String, String>,
) {
    /// Only the progress moved: the large widget's line is redrawn and nothing else.
    fun onlyPositionDiffers(other: WidgetState) = copy(positionMs = other.positionMs) == other

    fun label(key: String) = labels[key] ?: ""

    companion object {
        fun parse(json: String): WidgetState? = runCatching {
            val o = JSONObject(json)
            val l = o.optJSONObject("labels")
            WidgetState(
                hasTrack = o.optBoolean("track"),
                title = o.optString("title"),
                artist = o.optString("artist"),
                cover = o.optString("cover").ifEmpty { null },
                seed = o.optInt("seed"),
                playing = o.optBoolean("playing"),
                shuffle = o.optBoolean("shuffle"),
                repeat = o.optString("repeat", "none"),
                favorite = o.optBoolean("favorite"),
                positionMs = o.optLong("position"),
                durationMs = o.optLong("duration"),
                tint = o.optInt("tint", GLASS),
                labels = l?.keys()?.asSequence()?.associateWith { l.optString(it) } ?: emptyMap(),
            )
        }.getOrNull()

        /// AppColors.glassLevel2Solid without its alpha (the drawable keeps that).
        const val GLASS = 0xFF0E1F3C.toInt()
    }
}

object HomeWidgets {
    private const val PREFS = "home_widgets"
    private const val KEY_STATE = "state"

    private var state: WidgetState? = null
    private var loaded = false

    /// The last cover read, already sampled down: a play/pause or a progress tick doesn't
    /// read the file again.
    private var coverCache: Pair<String, Bitmap>? = null

    /// The app sent a new state.
    fun update(context: Context, json: String) {
        val next = WidgetState.parse(json) ?: return
        val previous = current(context)
        state = next
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_STATE, json).apply()

        val manager = AppWidgetManager.getInstance(context)
        val ids = WidgetKind.entries.associateWith { manager.getAppWidgetIds(it.provider(context)) }
        if (ids.values.all { it.isEmpty() }) return
        if (previous != null && next.onlyPositionDiffers(previous)) {
            // A progress tick: nobody sees it with the screen off
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val large = ids.getValue(WidgetKind.LARGE)
            if (power.isInteractive && large.isNotEmpty()) {
                val views = RemoteViews(context.packageName, R.layout.widget_large)
                setProgress(views, next)
                manager.partiallyUpdateAppWidget(large, views)
            }
            return
        }
        for ((kind, list) in ids) if (list.isNotEmpty()) render(context, manager, kind, list)
    }

    fun render(context: Context, manager: AppWidgetManager, kind: WidgetKind, ids: IntArray) {
        val s = current(context)
        for (id in ids) {
            runCatching { manager.updateAppWidget(id, views(context, manager, kind, id, s)) }
        }
    }

    private fun current(context: Context): WidgetState? {
        if (!loaded) {
            loaded = true
            state = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_STATE, null)?.let(WidgetState::parse)
        }
        return state
    }

    private fun views(context: Context, manager: AppWidgetManager, kind: WidgetKind, id: Int, s: WidgetState?): RemoteViews {
        val v = RemoteViews(context.packageName, kind.layout)
        v.setOnClickPendingIntent(android.R.id.background, openApp(context))

        if (s == null || !s.hasTrack) {
            // Just installed, nothing played yet: the name and a hint, tap opens the app
            v.setTextViewText(R.id.widget_title, s?.label("emptyTitle")?.ifEmpty { null } ?: context.getString(R.string.widget_empty_title))
            v.setTextViewText(R.id.widget_artist, s?.label("emptyHint")?.ifEmpty { null } ?: context.getString(R.string.widget_empty_hint))
            v.setImageViewBitmap(R.id.widget_art, art(context, manager, kind, id, null))
            for (button in buttonsOf(kind)) v.setViewVisibility(button, View.GONE)
            if (kind == WidgetKind.LARGE) v.setViewVisibility(R.id.widget_progress, View.INVISIBLE)
            return v
        }

        v.setTextViewText(R.id.widget_title, s.title)
        v.setTextViewText(R.id.widget_artist, s.artist)
        v.setImageViewBitmap(R.id.widget_art, art(context, manager, kind, id, s))
        if (kind != WidgetKind.SMALL) v.setInt(R.id.widget_fill, "setColorFilter", s.tint)

        // The service is gone (the app was ended, the phone restarted): nothing plays, whatever
        // was last sent
        val playing = s.playing && PlaybackServiceControl.running()
        v.setImageViewResource(R.id.widget_play, if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
        v.setContentDescription(R.id.widget_play, s.label(if (playing) "pause" else "play"))
        v.setOnClickPendingIntent(R.id.widget_play, mediaButton(context, PlaybackStateCompat.ACTION_PLAY_PAUSE))
        if (kind == WidgetKind.SMALL) return v

        v.setContentDescription(R.id.widget_previous, s.label("previous"))
        v.setContentDescription(R.id.widget_next, s.label("next"))
        v.setOnClickPendingIntent(R.id.widget_previous, mediaButton(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
        v.setOnClickPendingIntent(R.id.widget_next, mediaButton(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT))
        if (kind == WidgetKind.WIDE) return v

        setProgress(v, s)
        val cyan = ContextCompat.getColor(context, R.color.widget_cyan)
        val quiet = ContextCompat.getColor(context, R.color.widget_text_secondary)
        v.setInt(R.id.widget_shuffle, "setColorFilter", if (s.shuffle) cyan else quiet)
        v.setContentDescription(R.id.widget_shuffle, s.label(if (s.shuffle) "shuffleOn" else "shuffleOff"))
        v.setImageViewResource(R.id.widget_repeat, if (s.repeat == "one") R.drawable.ic_widget_repeat_one else R.drawable.ic_widget_repeat)
        v.setInt(R.id.widget_repeat, "setColorFilter", if (s.repeat == "none") quiet else cyan)
        v.setContentDescription(R.id.widget_repeat, s.label("repeat_${s.repeat}"))
        v.setImageViewResource(R.id.widget_favorite, if (s.favorite) R.drawable.ic_widget_favorite else R.drawable.ic_widget_favorite_border)
        v.setContentDescription(R.id.widget_favorite, s.label(if (s.favorite) "removeFavorite" else "addFavorite"))
        v.setOnClickPendingIntent(R.id.widget_shuffle, appAction(context, "shuffle"))
        v.setOnClickPendingIntent(R.id.widget_repeat, appAction(context, "repeat"))
        v.setOnClickPendingIntent(R.id.widget_favorite, appAction(context, "favorite"))
        return v
    }

    private fun buttonsOf(kind: WidgetKind) = when (kind) {
        WidgetKind.SMALL -> listOf(R.id.widget_play)
        WidgetKind.WIDE -> listOf(R.id.widget_previous, R.id.widget_play, R.id.widget_next)
        WidgetKind.LARGE -> listOf(R.id.widget_controls, R.id.widget_favorite)
    }

    private fun setProgress(v: RemoteViews, s: WidgetState) {
        val p = if (s.durationMs <= 0) 0 else (s.positionMs * 1000 / s.durationMs).toInt().coerceIn(0, 1000)
        v.setProgressBar(R.id.widget_progress, 1000, p, false)
    }

    // ── pictures ──────────────────────────────────────────

    /// The cover cut to the place it fills, with rounded corners (and AlbumArt's hairline on
    /// the two framed covers). No cover → AlbumArt's placeholder.
    private fun art(context: Context, manager: AppWidgetManager, kind: WidgetKind, id: Int, s: WidgetState?): Bitmap {
        val res = context.resources
        val density = res.displayMetrics.density
        val (w, h) = when (kind) {
            WidgetKind.SMALL -> {
                // Portrait size of this widget; unknown → square
                val o = manager.getAppWidgetOptions(id)
                val wDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                val hDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
                if (wDp <= 0 || hDp <= 0) 160 to 160 else wDp to hDp
            }
            WidgetKind.WIDE -> 48 to 48
            WidgetKind.LARGE -> {
                val hDp = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
                val side = if (hDp <= 0) 132 else (hDp - 28).coerceIn(88, 160)
                side to side
            }
        }
        // Long side at most 512 px: enough for a sharp cover, far under the widget picture limit
        val scale = min(density, 512f / max(w, h))
        val pw = max(1, (w * scale).roundToInt())
        val ph = max(1, (h * scale).roundToInt())
        val radius = res.getDimension(if (kind == WidgetKind.SMALL) R.dimen.widget_radius else R.dimen.widget_inner_radius) * scale / density

        val out = Bitmap.createBitmap(pw, ph, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val rect = RectF(0f, 0f, pw.toFloat(), ph.toFloat())
        val clip = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }
        canvas.clipPath(clip)

        val cover = s?.cover?.let { cover(it, max(pw, ph)) }
        if (cover != null) {
            // Centre crop, as BoxFit.cover
            val k = max(pw.toFloat() / cover.width, ph.toFloat() / cover.height)
            val sw = pw / k
            val sh = ph / k
            val left = (cover.width - sw) / 2
            val top = (cover.height - sh) / 2
            val src = Rect(left.roundToInt(), top.roundToInt(), (left + sw).roundToInt(), (top + sh).roundToInt())
            canvas.drawBitmap(cover, src, rect, Paint(Paint.FILTER_BITMAP_FLAG))
        } else {
            placeholder(context, canvas, rect, s?.seed ?: 0)
        }
        if (kind != WidgetKind.SMALL) {
            val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = scale
                color = ContextCompat.getColor(context, R.color.widget_art_border)
            }
            val inset = scale / 2
            canvas.drawRoundRect(RectF(inset, inset, pw - inset, ph - inset), radius, radius, border)
        }
        return out
    }

    /// AlbumArt's placeholder: the song's hue (dark) into void, the note in cyan at 70 %.
    private fun placeholder(context: Context, canvas: Canvas, rect: RectF, seed: Int) {
        val hue = ((seed.toLong() * 47) % 360 + 360) % 360
        val from = ColorUtils.HSLToColor(floatArrayOf(hue.toFloat(), .45f, .22f))
        val void = ContextCompat.getColor(context, R.color.nocturne_void)
        val paint = Paint().apply {
            shader = LinearGradient(rect.left, rect.top, rect.right, rect.bottom, from, void, Shader.TileMode.CLAMP)
        }
        canvas.drawRect(rect, paint)
        val icon = ContextCompat.getDrawable(context, R.drawable.ic_widget_cover_dim) ?: return
        val size = (min(rect.width(), rect.height()) * .4f).roundToInt()
        val cx = rect.centerX().roundToInt()
        val cy = rect.centerY().roundToInt()
        icon.setBounds(cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2)
        icon.draw(canvas)
    }

    /// The cover file read at about [side] px. Null if it can't be read (gone, broken).
    private fun cover(path: String, side: Int): Bitmap? {
        coverCache?.let { (p, b) -> if (p == path && max(b.width, b.height) >= side / 2) return b }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= max(side, 256)) sample *= 2
        val bitmap = runCatching {
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        }.getOrNull() ?: return null
        coverCache = path to bitmap
        return bitmap
    }

    // ── taps ──────────────────────────────────────────────

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /// The same intent a headset button sends, to audio_service's receiver.
    private fun mediaButton(context: Context, action: Long): PendingIntent =
        androidx.media.session.MediaButtonReceiver.buildMediaButtonPendingIntent(
            context,
            ComponentName(context, com.ryanheise.audioservice.MediaButtonReceiver::class.java),
            action,
        )

    private fun appAction(context: Context, name: String): PendingIntent {
        val intent = Intent(context, WidgetActionReceiver::class.java).setAction(WidgetActionReceiver.ACTION_PREFIX + name)
        return PendingIntent.getBroadcast(context, name.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE)
    }
}
