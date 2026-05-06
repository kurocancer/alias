package com.example.sailade

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler

/**
 * Main Activity implementing native sensor bridge for Flutter.
 * Uses MethodChannel for control and EventChannel for high-frequency sensor streaming.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CONTROL_CHANNEL = "com.saila.sensors/control"
        private const val STREAM_CHANNEL = "com.saila.sensors/stream"
    }

    private lateinit var sensorManager: SensorManager
    private var gyroscopeSensor: Sensor? = null
    private var sensorEventListener: SensorEventListener? = null
    private var eventSink: EventSink? = null

    /**
     * Configures Flutter engine with native communication channels
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        // Initialize sensor manager and gyroscope sensor
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        gyroscopeSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        // MethodChannel for start/stop commands from Flutter
        MethodChannel(binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startGyroscope()
                    result.success(true)
                }
                "stop" -> {
                    stopGyroscope()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel for streaming sensor data to Flutter
        EventChannel(binaryMessenger, STREAM_CHANNEL).setStreamHandler(object : StreamHandler {
            override fun onListen(arguments: Any?, events: EventSink?) {
                eventSink = events
                // Sensor activation is handled via MethodChannel, not here
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                stopGyroscope() // Stop sensors when Flutter cancels stream
            }
        })
    }

    /**
     * Registers gyroscope listener with high-frequency GAME delay
     */
    private fun startGyroscope() {
        if (gyroscopeSensor == null) {
            eventSink?.error("NO_GYROSCOPE", "Device does not have a gyroscope sensor", null)
            return
        }

        sensorEventListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent?) {
                if (event?.sensor?.type == Sensor.TYPE_GYROSCOPE) {
                    // Extract raw sensor values and send to Flutter
                    val x = event.values[0].toDouble()
                    val y = event.values[1].toDouble()
                    val z = event.values[2].toDouble()
                    val sensorData = mapOf("x" to x, "y" to y, "z" to z)
                    eventSink?.success(sensorData)
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                // No action needed for accuracy changes
            }
        }

        // Register listener with SENSOR_DELAY_GAME for high frequency (20ms interval)
        sensorManager.registerListener(
            sensorEventListener,
            gyroscopeSensor,
            SensorManager.SENSOR_DELAY_GAME
        )
    }

    /**
     * Unregisters sensor listener to save battery and prevent leaks
     */
    private fun stopGyroscope() {
        sensorEventListener?.let {
            sensorManager.unregisterListener(it)
            sensorEventListener = null
        }
    }

    /**
     * Clean up resources when activity is destroyed
     */
    override fun onDestroy() {
        super.onDestroy()
        stopGyroscope()
        eventSink = null
    }

    /**
     * Stop sensors when app is paused to save battery
     */
    override fun onPause() {
        super.onPause()
        stopGyroscope()
    }
}
