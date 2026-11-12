package com.echo.hearing.data

import android.content.Context
import com.echo.hearing.domain.model.HearingSessionRecord
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import java.io.File

/**
 * Interface for offline-first, privacy-preserving session persistence.
 */
interface SessionRepository {
    fun saveSession(session: HearingSessionRecord): Boolean
    fun getSession(sessionId: String): HearingSessionRecord?
    fun listSessions(): List<HearingSessionRecord>
    fun deleteSession(sessionId: String): Boolean
}

/**
 * Encrypted/app-private local storage repository using structured JSON files.
 * Zero cloud transmission. No raw audio captured or retained.
 */
class LocalJsonSessionRepository(
    private val context: Context,
    private val gson: Gson = GsonBuilder().setPrettyPrinting().create()
) : SessionRepository {

    private val sessionsDir: File by lazy {
        File(context.filesDir, "echo_sessions").apply {
            if (!exists()) mkdirs()
        }
    }

    override fun saveSession(session: HearingSessionRecord): Boolean {
        return try {
            val file = File(sessionsDir, "${session.sessionId}.json")
            val json = gson.toJson(session)
            file.writeText(json)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    override fun getSession(sessionId: String): HearingSessionRecord? {
        return try {
            val file = File(sessionsDir, "$sessionId.json")
            if (!file.exists()) return null
            gson.fromJson(file.readText(), HearingSessionRecord::class.java)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun listSessions(): List<HearingSessionRecord> {
        val files = sessionsDir.listFiles { _, name -> name.endsWith(".json") } ?: return emptyList()
        return files.mapNotNull { file ->
            try {
                gson.fromJson(file.readText(), HearingSessionRecord::class.java)
            } catch (e: Exception) {
                null
            }
        }.sortedByDescending { it.startedAt }
    }

    override fun deleteSession(sessionId: String): Boolean {
        val file = File(sessionsDir, "$sessionId.json")
        return if (file.exists()) file.delete() else false
    }
}

/**
 * Deterministic in-memory repository for unit tests.
 */
class InMemorySessionRepository : SessionRepository {
    private val storage = mutableMapOf<String, HearingSessionRecord>()

    override fun saveSession(session: HearingSessionRecord): Boolean {
        storage[session.sessionId] = session
        return true
    }

    override fun getSession(sessionId: String): HearingSessionRecord? {
        return storage[sessionId]
    }

    override fun listSessions(): List<HearingSessionRecord> {
        return storage.values.sortedByDescending { it.startedAt }
    }

    override fun deleteSession(sessionId: String): Boolean {
        return storage.remove(sessionId) != null
    }
}
