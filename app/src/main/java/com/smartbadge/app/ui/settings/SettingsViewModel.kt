package com.smartbadge.app.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.smartbadge.app.core.di.AppSettings
import com.smartbadge.app.core.di.SettingsDataStore
import com.smartbadge.app.core.network.ConnectivityChecker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TestResult(
    val name: String,
    val success: Boolean,
    val message: String
)

data class SettingsUiState(
    val asrUrl: String = "",
    val llmUrl: String = "",
    val llmKey: String = "",
    val llmModel: String = "",
    val llmPrompt: String = "",
    val isTesting: Boolean = false,
    val testResults: List<TestResult> = emptyList(),
    val showResults: Boolean = false
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsDataStore: SettingsDataStore,
    private val connectivityChecker: ConnectivityChecker
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            settingsDataStore.settingsFlow.collect { settings ->
                _uiState.value = _uiState.value.copy(
                    asrUrl = settings.asrUrl,
                    llmUrl = settings.llmUrl,
                    llmKey = settings.llmKey,
                    llmModel = settings.llmModel,
                    llmPrompt = settings.llmPrompt
                )
            }
        }
    }

    fun updateAsrUrl(url: String) {
        _uiState.value = _uiState.value.copy(asrUrl = url)
    }

    fun updateLlmUrl(url: String) {
        _uiState.value = _uiState.value.copy(llmUrl = url)
    }

    fun updateLlmKey(key: String) {
        _uiState.value = _uiState.value.copy(llmKey = key)
    }

    fun updateLlmModel(model: String) {
        _uiState.value = _uiState.value.copy(llmModel = model)
    }

    fun updateLlmPrompt(prompt: String) {
        _uiState.value = _uiState.value.copy(llmPrompt = prompt)
    }

    fun saveAndTest() {
        val state = _uiState.value
        _uiState.value = state.copy(isTesting = true, testResults = emptyList(), showResults = false)

        viewModelScope.launch {
            // Save all fields first
            settingsDataStore.updateAsrUrl(state.asrUrl)
            settingsDataStore.updateLlmUrl(state.llmUrl)
            settingsDataStore.updateLlmKey(state.llmKey)
            settingsDataStore.updateLlmModel(state.llmModel)
            settingsDataStore.updateLlmPrompt(state.llmPrompt)

            // Verify saved by reading back
            settingsDataStore.settingsFlow.first()

            // Run connectivity tests in parallel
            val asrDeferred = async {
                val result = connectivityChecker.checkAsrConnection(state.asrUrl)
                TestResult(
                    name = "语音识别 (FunASR)",
                    success = result.isSuccess,
                    message = result.getOrElse { it.message ?: "未知错误" }
                )
            }

            val llmDeferred = async {
                val result = connectivityChecker.checkLlmConnection(
                    state.llmUrl,
                    state.llmKey,
                    state.llmModel
                )
                TestResult(
                    name = "AI 总结 (LLM)",
                    success = result.isSuccess,
                    message = result.getOrElse { it.message ?: "未知错误" }
                )
            }

            val results = listOf(asrDeferred.await(), llmDeferred.await())

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
}