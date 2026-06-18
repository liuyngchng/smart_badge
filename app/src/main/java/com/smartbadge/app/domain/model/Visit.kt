package com.smartbadge.app.domain.model

import java.time.Instant

enum class ProcessingStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    UNAVAILABLE
}

data class Visit(
    val id: Long = 0,
    val clientName: String,
    val clientCompany: String = "",
    val purpose: String,
    val participants: List<String> = emptyList(),
    val startTime: Instant = Instant.now(),
    val endTime: Instant? = null,
    val locationPoints: List<LocationPoint> = emptyList(),
    val transcriptText: String = "",
    val transcriptStatus: ProcessingStatus = ProcessingStatus.PENDING,
    val summary: VisitSummary? = null,
    val summaryStatus: ProcessingStatus = ProcessingStatus.PENDING,
    val audioFilePath: String = "",
    val transcriptFilePath: String = "",
    val createdAt: Instant = Instant.now()
)

data class LocationPoint(
    val latitude: Double,
    val longitude: Double,
    val timestamp: Long
)
