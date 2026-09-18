package com.truckrouter.truck_router

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        criarCanalSos()
    }

    // "fom fom" do S.O.S. dentro do app (nav e ficha). Mesmo uso de áudio da voz
    // da navegação: segue o volume do guia. Responde só quando terminar, pra a
    // fala vir DEPOIS da buzina. Falhou = responde mesmo assim (a fala não pode
    // ficar esperando uma buzina que não toca).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "notrecho/som")
            .setMethodCallHandler { call, result ->
                if (call.method != "buzina") return@setMethodCallHandler result.notImplemented()
                try {
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val mp = MediaPlayer.create(this, R.raw.buzina, attrs, am.generateAudioSessionId())
                    if (mp == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    mp.setOnCompletionListener { it.release(); result.success(true) }
                    mp.start()
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }

    // Canal do push do S.O.S. Sem canal próprio o FCM usava o "Diversos" dele,
    // prioridade normal: sem pop-up, e o MIUI do Beto escondeu (18/09).
    // Som e importância são fixos na CRIAÇÃO do canal. "sos" (2.4.80, som
    // padrão) e "sos_buzina" (2.4.81, som pelo id NUMÉRICO do recurso, que pode
    // mudar entre builds) são apagados. O "sos_buzina2" aponta o som pelo NOME
    // (raw/buzina): trocar o arquivo muda a buzina sem precisar de canal novo.
    // O id é o mesmo do backend (sos_push.go) e do manifest; o teste
    // android_manifest_test amarra os três.
    private fun criarCanalSos() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        nm.deleteNotificationChannel("sos")
        nm.deleteNotificationChannel("sos_buzina")
        val som = Uri.parse("android.resource://$packageName/raw/buzina")
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val canal = NotificationChannel("sos_buzina2", "Pedido de ajuda", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Motorista perto de você pedindo ajuda na estrada"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            setSound(som, attrs)
        }
        nm.createNotificationChannel(canal)
    }
}
