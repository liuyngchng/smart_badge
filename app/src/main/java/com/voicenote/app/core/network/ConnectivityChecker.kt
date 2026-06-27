package com.voicenote.app.core.network

import com.google.gson.Gson
import com.voicenote.app.core.asr.ASRModelManager
import com.voicenote.app.core.asr.ModelQuality
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.io.File
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ConnectivityChecker @Inject constructor(
    private val asrModelManager: ASRModelManager
) {

    suspend fun checkAsrConnection(url: String): Result<String> = withContext(Dispatchers.IO) {
        if (url.isBlank()) return@withContext Result.failure(Exception("ASR 地址不能为空"))

        val client = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()

        val resultChannel = Channel<String>(Channel.CONFLATED)

        val request = Request.Builder().url(url).build()
        client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.close(1000, "connectivity test")
                client.dispatcher.executorService.shutdown()
                resultChannel.trySend("ok")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                client.dispatcher.executorService.shutdown()
                val msg = if (response != null) {
                    "HTTP ${response.code}: ${response.message}"
                } else {
                    t.message ?: "连接失败"
                }
                resultChannel.trySend("fail:$msg")
            }
        })

        val result = resultChannel.receive()
        if (result == "ok") {
            Result.success("WebSocket 连接成功")
        } else {
            Result.failure(Exception(result.removePrefix("fail:")))
        }
    }

    fun checkAsrOffline(quality: String): Result<String> {
        val q = if (quality == "fp32") ModelQuality.FP32 else ModelQuality.INT8
        val modelFile = File(asrModelManager.modelFilePath(q))
        val tokensFile = File(asrModelManager.tokensFilePath())

        return when {
            !modelFile.exists() || modelFile.length() < 1_000_000 ->
                Result.failure(Exception("离线 ASR 模型未下载 (${q.displayName})，请先下载"))
            !tokensFile.exists() ->
                Result.failure(Exception("tokens.txt 未找到，请重新下载模型"))
            else ->
                Result.success("离线 ASR 模型就绪 (${q.displayName}, ${modelFile.length() / 1_048_576}MB)")
        }
    }
}
