package com.smartbadge.app.core.network

import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ConnectivityChecker @Inject constructor() {

    private val gson = Gson()

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
                // Immediately close after connected
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

    suspend fun checkLlmConnection(
        url: String,
        apiKey: String,
        model: String
    ): Result<String> = withContext(Dispatchers.IO) {
        if (url.isBlank()) return@withContext Result.failure(Exception("API 地址不能为空"))
        if (apiKey.isBlank()) return@withContext Result.failure(Exception("API Key 不能为空"))

        val client = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(5, TimeUnit.SECONDS)
            .build()

        try {
            val body = JsonObject().apply {
                addProperty("model", model)
                val messages = JsonObject().apply {
                    addProperty("role", "user")
                    addProperty("content", "test")
                }
                add("messages", com.google.gson.JsonArray().apply { add(messages) })
                addProperty("max_tokens", 1)
            }

            val requestBody = gson.toJson(body).toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $apiKey")
                .post(requestBody)
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string() ?: ""
            response.close()
            client.dispatcher.executorService.shutdown()

            if (response.isSuccessful) {
                Result.success("API 连接成功（HTTP ${response.code}）")
            } else {
                Result.failure(Exception("HTTP ${response.code}: ${responseBody.take(100)}"))
            }
        } catch (e: Exception) {
            client.dispatcher.executorService.shutdown()
            Result.failure(Exception(e.message ?: "请求失败"))
        }
    }
}