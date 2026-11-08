package com.example.lumairie

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android 10+ local-only Wi-Fi request. Android shows the user its own approval
 * dialog; we bind only this app's sockets to the approved, no-internet network.
 * Disconnect after each send restores ordinary internet networking.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "io.lumarie.mobile/frame_ap"
    private val permissionRequest = 49162
    private val manager by lazy {
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var pendingPermission: Triple<String, String, MethodChannel.Result>? = null
    private var connectionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val ssid = call.argument<String>("ssid")
                        val password = call.argument<String>("password")
                        if (ssid == null || !Regex("^LUMAIRIE-[A-Fa-f0-9]{6}$").matches(ssid) ||
                            password == null || !Regex("^[a-fA-F0-9]{20}$").matches(password)
                        ) {
                            result.error("invalid_frame", "Scan the QR on your own Lumairie frame.", null)
                        } else {
                            connect(ssid, password, result)
                        }
                    }
                    "disconnect" -> {
                        releaseNetwork()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun connect(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("android_version",
                "Android 10 or newer is needed for automatic frame Wi-Fi connection.", null)
            return
        }
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.NEARBY_WIFI_DEVICES
        else Manifest.permission.ACCESS_FINE_LOCATION
        if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            if (pendingPermission != null) {
                result.error("busy", "A Wi-Fi permission request is in progress.", null)
                return
            }
            pendingPermission = Triple(ssid, password, result)
            requestPermissions(arrayOf(permission), permissionRequest)
            return
        }
        requestLocalNetwork(ssid, password, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            requestLocalNetwork(pending.first, pending.second, pending.third)
        } else {
            pending.third.error("permission_denied",
                "Allow Nearby devices / Location permission to join the frame Wi-Fi.", null)
        }
    }

    private fun requestLocalNetwork(
        ssid: String, password: String, result: MethodChannel.Result
    ) {
        releaseNetwork()
        try {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(password)
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            connectionResult = result
            val newCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    runOnUiThread {
                        if (callback !== this) return@runOnUiThread
                        val connected = manager.bindProcessToNetwork(network)
                        connectionResult?.let {
                            connectionResult = null
                            if (connected) it.success(true)
                            else {
                                it.error("route_failed", "Could not use the frame's Wi-Fi.", null)
                                releaseNetwork()
                            }
                        }
                    }
                }

                override fun onUnavailable() {
                    runOnUiThread {
                        if (callback !== this) return@runOnUiThread
                        connectionResult?.error("network_unavailable",
                            "Frame Wi-Fi unavailable or Android connection declined.", null)
                        connectionResult = null
                        releaseNetwork()
                    }
                }

                override fun onLost(network: Network) {
                    runOnUiThread {
                        if (callback !== this) return@runOnUiThread
                        connectionResult?.error("network_lost",
                            "Connection to the frame Wi-Fi was lost.", null)
                        connectionResult = null
                        releaseNetwork()
                    }
                }
            }
            callback = newCallback
            manager.requestNetwork(request, newCallback, 45000)
        } catch (e: Exception) {
            connectionResult = null
            releaseNetwork()
            result.error("wifi_error",
                "Could not join frame Wi-Fi. Turn on Wi-Fi and try again: ${e.javaClass.simpleName}", null)
        }
    }

    private fun releaseNetwork() {
        manager.bindProcessToNetwork(null)
        callback?.let {
            try { manager.unregisterNetworkCallback(it) } catch (_: Exception) {}
        }
        callback = null
        connectionResult?.error("cancelled", "Frame connection was cancelled.", null)
        connectionResult = null
    }

    override fun onDestroy() {
        pendingPermission?.third?.error("closed", "Wi-Fi request interrupted.", null)
        pendingPermission = null
        releaseNetwork()
        super.onDestroy()
    }
}
