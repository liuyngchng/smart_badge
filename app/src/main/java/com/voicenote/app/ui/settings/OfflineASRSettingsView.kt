package com.voicenote.app.ui.settings

import android.app.ActivityManager
import android.content.Context
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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.voicenote.app.core.asr.DownloadStatus
import com.voicenote.app.core.asr.ModelDownloadManager
import com.voicenote.app.core.asr.ModelQuality
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.launch

@Composable
fun OfflineASRSettingsView(
    asrMode: String,
    asrUrl: String,
    modelQuality: String,
    onAsrModeChange: (String) -> Unit,
    onAsrUrlChange: (String) -> Unit,
    onModelQualityChange: (String) -> Unit,
    downloadManager: ModelDownloadManager
) {
    val downloadState by downloadManager.downloadState.collectAsState()
    val context = LocalContext.current

    val totalRamGB = remember {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        memInfo.totalMem / (1024.0 * 1024 * 1024)
    }

    Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text("语音识别 (FunASR)", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)

        Spacer(modifier = Modifier.height(8.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ModeChip(
                label = "在线",
                selected = asrMode == "online",
                onClick = { onAsrModeChange("online") },
                modifier = Modifier.weight(1f)
            )
            ModeChip(
                label = "离线",
                selected = asrMode == "offline",
                onClick = { onAsrModeChange("offline") },
                modifier = Modifier.weight(1f)
            )
        }

        if (asrMode == "online") {
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = asrUrl,
                onValueChange = onAsrUrlChange,
                label = { Text("WebSocket 地址") },
                placeholder = { Text("ws://192.168.1.100:10095") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(8.dp)
            )
        }

        if (asrMode == "offline") {
            Spacer(modifier = Modifier.height(16.dp))

            Text("模型质量", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                QualityChip(
                    label = ModelQuality.INT8.displayName,
                    selected = modelQuality == "int8",
                    onClick = { onModelQualityChange("int8") },
                    modifier = Modifier.weight(1f)
                )
                QualityChip(
                    label = ModelQuality.FP32.displayName,
                    selected = modelQuality == "fp32",
                    onClick = { onModelQualityChange("fp32") },
                    modifier = Modifier.weight(1f)
                )
            }

            if (modelQuality == "fp32" && totalRamGB < 4.0) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "FP32 模型需要约 860MB 内存，当前设备内存仅 %.1f GB，可能无法正常加载，建议使用 INT8 模型。".format(totalRamGB),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f)
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            val quality = if (modelQuality == "fp32") ModelQuality.FP32 else ModelQuality.INT8
            val isDownloaded = downloadManager.isModelDownloaded(quality)
            val scope = rememberCoroutineScope()
            val filePicker = rememberLauncherForActivityResult(
                contract = ActivityResultContracts.OpenDocument()
            ) { uri ->
                uri?.let {
                    scope.launch(Dispatchers.IO) {
                        downloadManager.uploadModel(quality, it)
                    }
                }
            }

            when (downloadState.status) {
                DownloadStatus.IDLE -> {
                    if (isDownloaded) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("模型已就绪", color = MaterialTheme.colorScheme.primary)
                            Spacer(modifier = Modifier.weight(1f))
                            OutlinedButton(onClick = { downloadManager.deleteModel(quality) }) {
                                Text("删除模型")
                            }
                        }
                    } else {
                        Button(
                            onClick = {
                                scope.launch(Dispatchers.IO) {
                                    downloadManager.downloadModel(quality)
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("下载模型 (~${quality.estimatedSizeMB}MB)")
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
                DownloadStatus.DOWNLOADING -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.padding(start = 8.dp))
                        Text("处理中 ${(downloadState.progress * 100).toInt()}%")
                    }
                }
                DownloadStatus.EXTRACTING -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.padding(start = 8.dp))
                        Text("解压中...")
                    }
                }
                DownloadStatus.COMPLETED -> {
                    Text("模型已就绪", color = MaterialTheme.colorScheme.primary)
                }
                DownloadStatus.FAILED -> {
                    Column {
                        Text("失败: ${downloadState.error ?: "未知错误"}", color = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(
                            onClick = {
                                downloadManager.resetState()
                                scope.launch(Dispatchers.IO) {
                                    downloadManager.downloadModel(quality)
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
private fun QualityChip(
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
