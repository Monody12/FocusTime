package com.example.focus_my_time

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.CalendarContract
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "FocusMyTimeCalendar"
        private const val CALENDAR_CHANNEL = "com.focusmytime.android_calendar"
        private const val LOCAL_ACCOUNT_NAME = "FocusMyTime"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "focus_my_time/android_back"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createOrUpdateEvent" -> createOrUpdateEvent(call.arguments, result)
                "deleteEvent" -> deleteEvent(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun createOrUpdateEvent(arguments: Any?, result: MethodChannel.Result) {
        if (!hasCalendarPermissions()) {
            result.error("PERMISSION_DENIED", "Calendar permission is not granted", null)
            return
        }

        val args = arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGUMENT", "arguments are required", null)
            return
        }

        val calendarId = args["calendarId"] as? String
        val start = args["start"] as? Long
        val end = args["end"] as? Long
        if (calendarId.isNullOrBlank() || start == null || end == null) {
            result.error("INVALID_ARGUMENT", "calendarId, start and end are required", null)
            return
        }

        val eventId = (args["eventId"] as? String)?.toLongOrNull()
        val reminders = (args["reminders"] as? List<*>)
            ?.mapNotNull { (it as? Number)?.toInt() }
            ?: emptyList()

        try {
            val savedEventId = if (eventId == null) {
                insertEvent(calendarId, args, start, end)
            } else {
                updateEvent(eventId, args, start, end)
                eventId
            }

            upsertReminders(savedEventId, reminders)
            result.success(savedEventId.toString())
        } catch (error: Exception) {
            result.error("CALENDAR_WRITE_FAILED", error.message, null)
        }
    }

    private fun insertEvent(
        calendarId: String,
        args: Map<*, *>,
        start: Long,
        end: Long
    ): Long {
        val values = buildEventValues(args, start, end).apply {
            put(Events.CALENDAR_ID, calendarId.toLong())
        }
        val uri = contentResolver.insert(Events.CONTENT_URI, values)
            ?: throw IllegalStateException("Calendar provider returned no event Uri")
        return ContentUris.parseId(uri)
    }

    private fun updateEvent(eventId: Long, args: Map<*, *>, start: Long, end: Long) {
        val values = buildEventValues(args, start, end)
        val updateCount = contentResolver.update(
            ContentUris.withAppendedId(Events.CONTENT_URI, eventId),
            values,
            null,
            null
        )
        if (updateCount <= 0) {
            throw IllegalStateException("No existing event was updated")
        }
    }

    private fun deleteEvent(arguments: Any?, result: MethodChannel.Result) {
        if (!hasCalendarPermissions()) {
            result.error("PERMISSION_DENIED", "Calendar permission is not granted", null)
            return
        }

        val args = arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGUMENT", "arguments are required", null)
            return
        }

        val eventId = (args["eventId"] as? String)?.toLongOrNull()
        if (eventId == null) {
            result.error("INVALID_ARGUMENT", "eventId is required", null)
            return
        }

        val eventUri = ContentUris.withAppendedId(Events.CONTENT_URI, eventId)
        try {
            if (contentResolver.delete(eventUri, null, null) > 0) {
                result.success(true)
                return
            }
        } catch (error: Exception) {
            Log.w(TAG, "App delete failed for event $eventId", error)
        }

        try {
            val syncDeleteUri = ContentUris.withAppendedId(
                syncAdapterUri(Events.CONTENT_URI),
                eventId
            )
            if (contentResolver.delete(syncDeleteUri, null, null) > 0) {
                result.success(true)
                return
            }
        } catch (error: Exception) {
            Log.w(TAG, "Sync-adapter delete fallback failed for event $eventId", error)
        }

        val now = System.currentTimeMillis()
        val cancelValues = ContentValues().apply {
            put(Events.TITLE, "（已取消）FocusMyTime 提醒")
            put(Events.DTSTART, now)
            put(Events.DTEND, now + 60_000)
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(Events.EVENT_END_TIMEZONE, TimeZone.getDefault().id)
            put(Events.STATUS, Events.STATUS_CANCELED)
        }

        var cancelCount = try {
            contentResolver.update(eventUri, cancelValues, null, null)
        } catch (error: Exception) {
            Log.w(TAG, "Cancel update failed for event $eventId", error)
            0
        }
        if (cancelCount <= 0) {
            cancelCount = try {
                contentResolver.update(
                    ContentUris.withAppendedId(syncAdapterUri(Events.CONTENT_URI), eventId),
                    cancelValues,
                    null,
                    null
                )
            } catch (error: Exception) {
                Log.w(TAG, "Sync-adapter cancel update failed for event $eventId", error)
                0
            }
        }
        upsertReminders(eventId, emptyList())
        result.success(cancelCount > 0)
    }

    private fun buildEventValues(args: Map<*, *>, start: Long, end: Long): ContentValues {
        val status = args["status"] as? String
        return ContentValues().apply {
            put(Events.DTSTART, start)
            put(Events.DTEND, end)
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(Events.EVENT_END_TIMEZONE, TimeZone.getDefault().id)
            put(Events.TITLE, args["title"] as? String ?: "FocusMyTime 提醒")
            put(Events.DESCRIPTION, args["description"] as? String)
            put(Events.AVAILABILITY, Events.AVAILABILITY_BUSY)
            mapEventStatus(status)?.let { put(Events.STATUS, it) }
        }
    }

    private fun upsertReminders(eventId: Long, reminderMinutes: List<Int>) {
        val reminderIds = mutableListOf<Long>()
        val cursor = Reminders.query(contentResolver, eventId, arrayOf(Reminders._ID))
        cursor?.use {
            while (it.moveToNext()) {
                reminderIds.add(it.getLong(0))
            }
        }

        if (reminderMinutes.isEmpty()) {
            reminderIds.forEach { reminderId ->
                deleteReminderBestEffort(reminderId)
            }
            return
        }

        reminderMinutes.forEachIndexed { index, minutes ->
            val values = ContentValues().apply {
                put(Reminders.MINUTES, minutes)
                put(Reminders.METHOD, Reminders.METHOD_ALERT)
            }
            val reminderId = reminderIds.getOrNull(index)
            if (reminderId != null) {
                contentResolver.update(
                    ContentUris.withAppendedId(Reminders.CONTENT_URI, reminderId),
                    values,
                    null,
                    null
                )
            } else {
                values.put(Reminders.EVENT_ID, eventId)
                contentResolver.insert(Reminders.CONTENT_URI, values)
            }
        }

        reminderIds.drop(reminderMinutes.size).forEach { reminderId ->
            deleteReminderBestEffort(reminderId)
        }
    }

    private fun deleteReminderBestEffort(reminderId: Long) {
        try {
            contentResolver.delete(
                ContentUris.withAppendedId(Reminders.CONTENT_URI, reminderId),
                null,
                null
            )
        } catch (error: Exception) {
            Log.w(TAG, "Deleting reminder $reminderId failed", error)
        }
    }

    private fun syncAdapterUri(uri: Uri): Uri {
        return uri.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, LOCAL_ACCOUNT_NAME)
            .appendQueryParameter(
                CalendarContract.Calendars.ACCOUNT_TYPE,
                CalendarContract.ACCOUNT_TYPE_LOCAL
            )
            .build()
    }

    private fun mapEventStatus(status: String?): Int? {
        return when (status) {
            "Confirmed" -> Events.STATUS_CONFIRMED
            "Canceled" -> Events.STATUS_CANCELED
            "Tentative" -> Events.STATUS_TENTATIVE
            else -> null
        }
    }

    private fun hasCalendarPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.WRITE_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
    }
}
