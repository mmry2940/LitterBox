package lit.terssh.box

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "adb_usb"
	private val EVENTS_CHANNEL = "adb_usb_events"
	private val ACTION_USB_PERMISSION = "lit.terssh.box.USB_PERMISSION"
	private var usbManager: UsbManager? = null
	private var permissionPending = false
	private var eventsSink: EventChannel.EventSink? = null

	private val usbReceiver = object : BroadcastReceiver() {
		override fun onReceive(context: Context?, intent: Intent?) {
			if (intent?.action == ACTION_USB_PERMISSION) {
				synchronized(this) {
					val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
					val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
					// We don't have a direct callback to Dart; next enumerate will reflect permission
				}
			}
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		
		try {
			usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
			registerReceiver(usbReceiver, IntentFilter(ACTION_USB_PERMISSION))

			// Hotplug (attach/detach) receiver
			val hotplugFilter = IntentFilter()
			hotplugFilter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
			hotplugFilter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
			registerReceiver(hotplugReceiver, hotplugFilter)
		} catch (e: Exception) {
			android.util.Log.e("MainActivity", "Error setting up USB: ${e.message}", e)
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"listDevices" -> {
					val devices = usbManager?.deviceList?.values?.map { d ->
						mapOf(
							"vendorId" to d.vendorId,
							"productId" to d.productId,
							"deviceId" to d.deviceId,
							"serial" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) d.serialNumber else null),
							"name" to d.deviceName,
							"hasPermission" to (usbManager?.hasPermission(d) ?: false)
						)
					} ?: emptyList()
					result.success(devices)
				}
				"requestPermission" -> {
					val deviceId = call.argument<Int>("deviceId")
					val device = usbManager?.deviceList?.values?.firstOrNull { it.deviceId == deviceId }
					if (device == null) {
						result.error("not_found", "Device not found", null)
					} else {
						val intent = PendingIntent.getBroadcast(
							this,
							0,
							Intent(ACTION_USB_PERMISSION),
							PendingIntent.FLAG_IMMUTABLE
						)
						usbManager?.requestPermission(device, intent)
						result.success(true)
					}
				}
				else -> result.notImplemented()
			}
		}

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL).setStreamHandler(object: EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				eventsSink = events
				// Immediately send current snapshot
				eventsSink?.success(mapOf("event" to "snapshot", "devices" to currentDevices()))
			}
			override fun onCancel(arguments: Any?) { eventsSink = null }
		})
	}

	private fun currentDevices(): List<Map<String, Any?>> {
		return usbManager?.deviceList?.values?.map { d ->
			mapOf(
				"vendorId" to d.vendorId,
				"productId" to d.productId,
				"deviceId" to d.deviceId,
				"serial" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) d.serialNumber else null),
				"name" to d.deviceName,
				"hasPermission" to (usbManager?.hasPermission(d) ?: false)
			)
		} ?: emptyList()
	}

	private val hotplugReceiver = object: BroadcastReceiver() {
		override fun onReceive(context: Context?, intent: Intent?) {
			val action = intent?.action ?: return
			when (action) {
				UsbManager.ACTION_USB_DEVICE_ATTACHED -> eventsSink?.success(mapOf("event" to "attached", "devices" to currentDevices()))
				UsbManager.ACTION_USB_DEVICE_DETACHED -> eventsSink?.success(mapOf("event" to "detached", "devices" to currentDevices()))
			}
		}
	}

	override fun onDestroy() {
		unregisterReceiver(usbReceiver)
		try { unregisterReceiver(hotplugReceiver) } catch (_: Exception) {}
		super.onDestroy()
	}
}
