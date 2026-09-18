package com.truckrouter.truck_router

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        criarCanalSos()
    }

    // Canal do push do S.O.S. Sem canal próprio o FCM usava o "Diversos" dele,
    // prioridade normal: sem pop-up, e o MIUI do Beto escondeu (18/09: badge "1"
    // no ícone, nada na barra). Importância fixa na CRIAÇÃO — depois quem manda
    // é o motorista nas configurações; mudar aqui não altera canal já criado.
    // O id "sos" é o mesmo do backend (sos_push.go) e do manifest; o teste
    // android_manifest_test amarra os três.
    private fun criarCanalSos() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel("sos", "Pedido de ajuda", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Motorista perto de você pedindo ajuda na estrada"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }
}
