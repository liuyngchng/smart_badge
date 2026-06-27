package com.voicenote.app.ui.settings

import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.voicenote.app.core.asr.ASRModelManager
import com.voicenote.app.core.asr.DownloadStatus
import com.voicenote.app.core.di.AppSettings
import com.voicenote.app.core.di.SettingsDataStore
import com.voicenote.app.core.network.ConnectivityChecker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class TestResult(
    val name: String,
    val success: Boolean,
    val message: String
)

data class ModelInfo(
    val name: String,
    val fileName: String,
    val isDownloaded: Boolean,
    val fileSize: Long,
    val isDownloading: Boolean = false,
    val downloadProgress: Float = 0f,
    val statusText: String = "",
    val downloadUrl: String? = null
)

data class SettingsUiState(
    val isLoading: Boolean = true,
    val asrUrl: String = "",
    val asrMode: String = "offline",
    val offlineModelQuality: String = "int8",
    val isTesting: Boolean = false,
    val testResults: List<TestResult> = emptyList(),
    val showResults: Boolean = false,
    val saveCount: Int = 0,
    val punctModel: ModelInfo = ModelInfo("标点模型", "punct_ct_transformer.onnx", false, 0)
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsDataStore: SettingsDataStore,
    private val connectivityChecker: ConnectivityChecker,
    private val asrModelManager: ASRModelManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    private var punctIsDownload = true // true = download, false = import

    init {
        viewModelScope.launch {
            settingsDataStore.settingsFlow.collect { settings ->
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    asrUrl = settings.asrUrl,
                    asrMode = settings.asrMode,
                    offlineModelQuality = settings.offlineModelQuality
                )
            }
        }
        // Observe punctuation model download/import progress persistently
        viewModelScope.launch {
            asrModelManager.punctDownloadState.collect { state ->
                if (_uiState.value.punctModel.isDownloading) {
                    _uiState.value = _uiState.value.copy(
                        punctModel = _uiState.value.punctModel.copy(
                            downloadProgress = state.progress,
                            statusText = when (state.status) {
                                DownloadStatus.DOWNLOADING -> "正在下载模型..."
                                DownloadStatus.UPLOADING -> "正在复制模型..."
                                DownloadStatus.EXTRACTING -> "正在提取模型..."
                                else -> ""
                            },
                            isDownloading = state.status == DownloadStatus.DOWNLOADING
                                    || state.status == DownloadStatus.UPLOADING
                                    || state.status == DownloadStatus.EXTRACTING,
                            downloadUrl = state.downloadUrl
                        )
                    )
                }
            }
        }
        refreshModelStatus()
    }

    fun refreshModelStatus() {
        val punctFile = File(asrModelManager.punctuationModelFilePath())
        val punctState = asrModelManager.punctDownloadState.value
        val opLabel = if (punctIsDownload) "下载" else "导入"
        _uiState.value = _uiState.value.copy(
            punctModel = ModelInfo(
                name = "标点模型",
                fileName = "punct_ct_transformer.onnx",
                isDownloaded = punctFile.exists(),
                fileSize = if (punctFile.exists()) punctFile.length() else 0,
                statusText = when (punctState.status) {
                    DownloadStatus.COMPLETED -> "${opLabel}完成"
                    DownloadStatus.FAILED -> "${opLabel}失败: ${punctState.error ?: ""}"
                    else -> ""
                },
                downloadUrl = punctState.downloadUrl
            )
        )
    }

    fun downloadPunctuationModel() {
        val current = _uiState.value.punctModel
        if (current.isDownloading) return
        punctIsDownload = true
        _uiState.value = _uiState.value.copy(
            punctModel = current.copy(isDownloading = true, downloadProgress = 0f, statusText = "准备下载...")
        )
        viewModelScope.launch {
            asrModelManager.downloadPunctuationModel()
                .onSuccess { Log.i(TAG, "Punctuation model downloaded successfully") }
                .onFailure { e -> Log.e(TAG, "Punctuation model download failed: ${e.message}") }
            refreshModelStatus()
        }
    }

    fun deletePunctuationModel() {
        val file = File(asrModelManager.punctuationModelFilePath())
        if (file.exists()) file.delete()
        refreshModelStatus()
    }

    fun importPunctuationModel(uri: Uri) {
        val current = _uiState.value.punctModel
        if (current.isDownloading) return
        punctIsDownload = false
        _uiState.value = _uiState.value.copy(
            punctModel = current.copy(isDownloading = true, downloadProgress = 0f, statusText = "正在导入...")
        )
        viewModelScope.launch {
            asrModelManager.importPunctuationArchive(uri)
                .onSuccess { Log.i(TAG, "Punctuation model imported successfully") }
                .onFailure { e -> Log.e(TAG, "Punctuation model import failed: ${e.message}") }
            refreshModelStatus()
        }
    }

    fun updateAsrUrl(url: String) {
        _uiState.value = _uiState.value.copy(asrUrl = url)
    }

    fun updateAsrMode(mode: String) {
        _uiState.value = _uiState.value.copy(asrMode = mode)
        viewModelScope.launch { settingsDataStore.updateAsrMode(mode) }
    }

    fun updateOfflineModelQuality(quality: String) {
        _uiState.value = _uiState.value.copy(offlineModelQuality = quality)
        viewModelScope.launch { settingsDataStore.updateOfflineModelQuality(quality) }
    }

    fun save() {
        val state = _uiState.value
        viewModelScope.launch {
            settingsDataStore.updateAsrUrl(state.asrUrl)
            settingsDataStore.updateAsrMode(state.asrMode)
            settingsDataStore.updateOfflineModelQuality(state.offlineModelQuality)
            _uiState.value = _uiState.value.copy(saveCount = _uiState.value.saveCount + 1)
        }
    }

    fun buildSaveSummary(): String {
        val s = _uiState.value
        val asr = if (s.asrMode == "offline") "离线(${s.offlineModelQuality.uppercase()})" else "在线"
        return "已保存 · 语音识别: $asr"
    }

    fun testConnection() {
        val state = _uiState.value
        _uiState.value = state.copy(isTesting = true, testResults = emptyList(), showResults = false)

        viewModelScope.launch {
            val results = mutableListOf<TestResult>()

            if (state.asrMode == "online") {
                val result = connectivityChecker.checkAsrConnection(state.asrUrl)
                results.add(TestResult(
                    name = "语音识别",
                    success = result.isSuccess,
                    message = result.getOrElse { it.message ?: "未知错误" }
                ))
            } else {
                val result = connectivityChecker.checkAsrOffline(state.offlineModelQuality)
                results.add(TestResult(
                    name = "语音识别 (离线)",
                    success = result.isSuccess,
                    message = result.getOrElse { it.message ?: "未知错误" }
                ))
            }

            _uiState.value = _uiState.value.copy(
                isTesting = false,
                testResults = results,
                showResults = true
            )
        }
    }

    fun dismissResults() {
        _uiState.value = _uiState.value.copy(showResults = false, testResults = emptyList())
    }

    companion object {
        private const val TAG = "SettingsViewModel"
    }
}
