package com.smartbadge.app.data.repository

import com.smartbadge.app.core.database.VisitDao
import com.smartbadge.app.core.database.VisitEntity
import com.smartbadge.app.domain.model.Visit
import com.smartbadge.app.domain.model.VisitSummary
import com.smartbadge.app.domain.repository.VisitRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VisitRepositoryImpl @Inject constructor(
    private val visitDao: VisitDao
) : VisitRepository {

    override fun getAllVisitsFlow(): Flow<List<Visit>> =
        visitDao.getAllFlow().map { entities -> entities.map { it.toDomain() } }

    override fun searchVisitsFlow(query: String): Flow<List<Visit>> =
        visitDao.searchFlow(query).map { entities -> entities.map { it.toDomain() } }

    override fun getVisitsByDateRangeFlow(fromEpochMillis: Long, toEpochMillis: Long): Flow<List<Visit>> =
        visitDao.getByDateRangeFlow(fromEpochMillis, toEpochMillis).map { entities ->
            entities.map { it.toDomain() }
        }

    override suspend fun getVisitById(id: Long): Visit? =
        visitDao.getById(id)?.toDomain()

    override fun getVisitByIdFlow(id: Long): Flow<Visit?> =
        visitDao.getByIdFlow(id).map { it?.toDomain() }

    override suspend fun createVisit(visit: Visit): Long =
        visitDao.insert(VisitEntity.fromDomain(visit))

    override suspend fun updateVisit(visit: Visit) {
        visitDao.update(VisitEntity.fromDomain(visit))
    }

    override suspend fun updateTranscript(id: Long, text: String) {
        val entity = visitDao.getById(id) ?: return
        visitDao.update(entity.copy(transcriptText = text))
    }

    override suspend fun updateTranscriptWithFile(id: Long, text: String, transcriptFilePath: String) {
        val entity = visitDao.getById(id) ?: return
        visitDao.update(entity.copy(transcriptText = text, transcriptFilePath = transcriptFilePath))
    }

    override suspend fun updateSummary(id: Long, summary: VisitSummary) {
        val entity = visitDao.getById(id) ?: return
        visitDao.update(
            entity.copy(
                topicsJson = com.google.gson.Gson().toJson(summary.topics),
                conclusionsJson = com.google.gson.Gson().toJson(summary.conclusions),
                todosJson = com.google.gson.Gson().toJson(summary.todos),
                nextSteps = summary.nextSteps,
                summaryStatus = com.smartbadge.app.domain.model.ProcessingStatus.COMPLETED.name
            )
        )
    }

    override suspend fun updateTranscriptStatus(id: Long, status: com.smartbadge.app.domain.model.ProcessingStatus) {
        val entity = visitDao.getById(id) ?: return
        visitDao.update(entity.copy(transcriptStatus = status.name))
    }

    override suspend fun updateSummaryStatus(id: Long, status: com.smartbadge.app.domain.model.ProcessingStatus) {
        val entity = visitDao.getById(id) ?: return
        visitDao.update(entity.copy(summaryStatus = status.name))
    }

    override suspend fun updateAudioFilePath(id: Long, path: String, endTime: java.time.Instant, locationPoints: List<com.smartbadge.app.domain.model.LocationPoint>) {
        val entity = visitDao.getById(id) ?: return
        visitDao.update(
            entity.copy(
                audioFilePath = path,
                endTime = endTime.toEpochMilli(),
                locationPointsJson = com.google.gson.Gson().toJson(locationPoints)
            )
        )
    }

    override suspend fun deleteVisit(id: Long) {
        visitDao.deleteById(id)
    }

    override suspend fun getAllClientNames(): List<String> =
        visitDao.getAllClientNames()
}
