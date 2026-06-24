#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

#include "sherpa-onnx/c-api/c-api.h"

#define TAG "SherpaOnnxJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

JNIEXPORT jlong JNICALL
Java_com_voicenote_app_core_asr_OfflineASRClient_nativeCreateRecognizer(
    JNIEnv *env, jclass clazz, jstring modelPath, jstring tokensPath) {

    const char *c_model = (*env)->GetStringUTFChars(env, modelPath, NULL);
    const char *c_tokens = (*env)->GetStringUTFChars(env, tokensPath, NULL);

    if (!c_model || !c_tokens) {
        LOGE("Failed to get path strings");
        if (c_model) (*env)->ReleaseStringUTFChars(env, modelPath, c_model);
        return 0;
    }

    LOGI("Creating recognizer: model=%s, tokens=%s", c_model, c_tokens);

    SherpaOnnxOfflineRecognizerConfig config;
    memset(&config, 0, sizeof(config));

    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;

    config.model_config.sense_voice.model = c_model;
    config.model_config.sense_voice.language = "auto";
    config.model_config.sense_voice.use_itn = 1;

    config.model_config.tokens = c_tokens;
    config.model_config.num_threads = 1;
    config.model_config.provider = "cpu";
    config.model_config.debug = 0;

    config.decoding_method = "greedy_search";

    const SherpaOnnxOfflineRecognizer *recognizer =
        SherpaOnnxCreateOfflineRecognizer(&config);

    (*env)->ReleaseStringUTFChars(env, modelPath, c_model);
    (*env)->ReleaseStringUTFChars(env, tokensPath, c_tokens);

    if (!recognizer) {
        LOGE("Failed to create recognizer");
        return 0;
    }

    LOGI("Recognizer created successfully");
    return (jlong)(intptr_t)recognizer;
}

JNIEXPORT jstring JNICALL
Java_com_voicenote_app_core_asr_OfflineASRClient_nativeRecognize(
    JNIEnv *env, jclass clazz, jlong recognizerPtr, jfloatArray samples) {

    if (recognizerPtr == 0) {
        LOGE("Null recognizer pointer");
        return NULL;
    }

    const SherpaOnnxOfflineRecognizer *recognizer =
        (const SherpaOnnxOfflineRecognizer *)(intptr_t)recognizerPtr;

    const SherpaOnnxOfflineStream *stream =
        SherpaOnnxCreateOfflineStream(recognizer);

    if (!stream) {
        LOGE("Failed to create offline stream");
        return NULL;
    }

    jsize n = (*env)->GetArrayLength(env, samples);
    jfloat *c_samples = (*env)->GetFloatArrayElements(env, samples, NULL);

    if (!c_samples) {
        LOGE("Failed to get sample array");
        SherpaOnnxDestroyOfflineStream(stream);
        return NULL;
    }

    SherpaOnnxAcceptWaveformOffline(stream, 16000, c_samples, n);
    SherpaOnnxDecodeOfflineStream(recognizer, stream);

    const SherpaOnnxOfflineRecognizerResult *result =
        SherpaOnnxGetOfflineStreamResult(stream);

    jstring j_text = NULL;
    if (result && result->text) {
        j_text = (*env)->NewStringUTF(env, result->text);
    }

    if (result) {
        SherpaOnnxDestroyOfflineRecognizerResult(result);
    }

    (*env)->ReleaseFloatArrayElements(env, samples, c_samples, JNI_ABORT);
    SherpaOnnxDestroyOfflineStream(stream);

    return j_text;
}

JNIEXPORT void JNICALL
Java_com_voicenote_app_core_asr_OfflineASRClient_nativeDestroyRecognizer(
    JNIEnv *env, jclass clazz, jlong recognizerPtr) {

    if (recognizerPtr == 0) return;

    const SherpaOnnxOfflineRecognizer *recognizer =
        (const SherpaOnnxOfflineRecognizer *)(intptr_t)recognizerPtr;

    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    LOGI("Recognizer destroyed");
}
