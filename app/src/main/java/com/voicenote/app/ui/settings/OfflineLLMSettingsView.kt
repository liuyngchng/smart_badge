package com.voicenote.app.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.voicenote.app.core.llm.LLMDownloadStatus
import com.voicenote.app.core.llm.LLMModelInfo
import com.voicenote.app.core.llm.LLMModelManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

@Composable
fun OfflineLLMSettingsView(
    llmMode: String,
    llmUrl: String,
    llmKey: String,
    llmModel: String,
    llmModelInfo: String,
    onLlmModeChange: (String) -> Unit,
    onLlmUrlChange: (String) -> Unit,
    onLlmKeyChange: (String) -> Unit,
    onLlmModelChange: (String) -> Unit,
    onLlmModelInfoChange: (String) -> Unit,
    modelManager: LLMModelManager
) {
    val downloadState by modelManager.downloadState.collectAsState()
    var keyVisible by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text("AI 总结 (OpenAI 兼容)", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)

        Spacer(modifier = Modifier.height(8.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ModeChip(
                label = "在线",
                selected = llmMode == "online",
                onClick = { onLlmModeChange("online") },
                modifier = Modifier.weight(1f)
            )
            ModeChip(
                label = "离线",
                selected = llmMode == "offline",
                onClick = { onLlmModeChange("offline") },
                modifier = Modifier.weight(1f)
            )
        }

        if (llmMode == "online") {
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = llmUrl,
                onValueChange = onLlmUrlChange,
                label = { Text("API 地址") },
                placeholder = { Text("https://api.deepseek.com") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(8.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = llmKey,
                onValueChange = onLlmKeyChange,
                label = { Text("API Key") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(8.dp),
                visualTransformation = if (keyVisible) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    IconButton(onClick = { keyVisible = !keyVisible }) {
                        Icon(
                            imageVector = if (keyVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (keyVisible) "隐藏 API Key" else "显示 API Key"
                        )
                    }
                }
            )
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = llmModel,
                onValueChange = onLlmModelChange,
                label = { Text("模型") },
                placeholder = { Text("gpt-4o-mini") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(8.dp)
            )
        }

        if (llmMode == "offline") {
            Spacer(modifier = Modifier.height(16.dp))

            Text("模型选择", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))

            val models = listOf(
                "qwen2_5_0_5b_q4km" to LLMModelInfo.QWEN2_5_0_5B,
                "qwen2_5_1_5b_q4km" to LLMModelInfo.QWEN2_5_1_5B,
                "custom" to LLMModelInfo.CUSTOM
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                models.forEach { (key, info) ->
                    ModelChip(
                        label = info.displayName,
                        selected = llmModelInfo == key,
                        onClick = { onLlmModelInfoChange(key) },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            val info = LLMModelInfo.fromString(llmModelInfo)
            val isDownloaded = modelManager.isModelDownloaded(info)
            val scope = rememberCoroutineScope()
            val filePicker = rememberLauncherForActivityResult(
                contract = ActivityResultContracts.OpenDocument()
            ) { uri ->
                uri?.let {
                    scope.launch(Dispatchers.IO) {
                        modelManager.uploadModel(info, it)
                    }
                }
            }

            when (downloadState.status) {
                LLMDownloadStatus.IDLE -> {
                    if (isDownloaded) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("模型已就绪 (${modelManager.downloadedModelSize(info) / 1_048_576}MB)", color = MaterialTheme.colorScheme.primary)
                            Spacer(modifier = Modifier.weight(1f))
                            OutlinedButton(onClick = { modelManager.deleteModel(info) }) {
                                Text("删除模型")
                            }
                        }
                    } else {
                        Button(
                            onClick = {
                                scope.launch(Dispatchers.IO) {
                                    modelManager.downloadModel(info)
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("下载模型 (~${info.estimatedSizeMB}MB)")
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(
                            onClick = { filePicker.launch(arrayOf("*/*")) },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("上传模型")
                        }
                    }
                }
                LLMDownloadStatus.DOWNLOADING -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.padding(start = 8.dp))
                        Text("处理中 ${(downloadState.progress * 100).toInt()}%")
                    }
                }
                LLMDownloadStatus.COMPLETED -> {
                    Text("模型已就绪", color = MaterialTheme.colorScheme.primary)
                }
                LLMDownloadStatus.FAILED -> {
                    Column {
                        Text("失败: ${downloadState.error ?: "未知错误"}", color = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(
                            onClick = {
                                modelManager.resetState()
                                scope.launch(Dispatchers.IO) {
                                    modelManager.downloadModel(info)
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("重试下载")
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(
                            onClick = { filePicker.launch(arrayOf("*/*")) },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("上传模型")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ModeChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(40.dp),
        shape = RoundedCornerShape(8.dp),
        colors = if (selected)
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
        else
            ButtonDefaults.outlinedButtonColors()
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun ModelChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(40.dp),
        shape = RoundedCornerShape(8.dp),
        colors = if (selected)
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
        else
            ButtonDefaults.outlinedButtonColors()
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
        )
    }
}
