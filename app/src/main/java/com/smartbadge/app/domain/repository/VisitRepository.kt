package com.smartbadge.app.domain.repository

import com.smartbadge.app.domain.model.Visit
import com.smartbadge.app.domain.model.VisitSummary
import kotlinx.coroutines.flow.Flow

interface VisitRepository {
    fun getAllVisitsFlow(): Flow<List<Visit>>
    fun searchVisitsFlow(query: String): Flow<List<Visit>>
    fun getVisitsByDateRangeFlow(fromEpochMillis: Long, toEpochMillis: Long): Flow<List<Visit>>
    suspend fun getVisitById(id: Long): Visit?
    fun getVisitByIdFlow(id: Long): Flow<Visit?>
    suspend fun createVisit(visit: Visit): Long
    suspend fun updateVisit(visit: Visit)
    suspend fun updateTranscript(id: Long, text: String)
    suspend fun updateTranscriptWithFile(id: Long, text: String, transcriptFilePath: String)
    suspend fun updateSummary(id: Long, summary: VisitSummary)
    suspend fun updateTranscriptStatus(id: Long, status: com.smartbadge.app.domain.model.ProcessingStatus)
    suspend fun updateSummaryStatus(id: Long, status: com.smartbadge.app.domain.model.ProcessingStatus)
    suspend fun updateAudioFilePath(id: Long, path: String, endTime: java.time.Instant, locationPoints: List<com.smartbadge.app.domain.model.LocationPoint>)
    suspend fun deleteVisit(id: Long)
    suspend fun getAllClientNames(): List<String>
}
