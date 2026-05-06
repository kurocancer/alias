import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SailaDemoApp());
}

/// Root application widget with dark theme configuration
class SailaDemoApp extends StatelessWidget {
  const SailaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Saila - Behavioral Biometrics',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Sleek dark blue
      ),
      home: const BiometricLoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Main screen handling login UI and biometric data collection
class BiometricLoginScreen extends StatefulWidget {
  const BiometricLoginScreen({super.key});

  @override
  State<BiometricLoginScreen> createState() => _BiometricLoginScreenState();
}

class _BiometricLoginScreenState extends State<BiometricLoginScreen> {
  // Native communication channels
  static const MethodChannel _controlChannel =
      MethodChannel('com.saila.sensors/control');
  static const EventChannel _sensorStream =
      EventChannel('com.saila.sensors/stream');

  // Focus nodes to manage sensor lifecycle based on text field interaction
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  // Telemetry console data
  List<String> liveTelemetry = [];
  bool isRecording = false;

  // Dart Isolate for background data processing (prevents UI jank)
  Isolate? _backgroundIsolate;
  ReceivePort? _mainReceivePort;
  SendPort? _isolateSendPort;
  StreamSubscription? _sensorSubscription;
  final ScrollController _telemetryScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeBackgroundIsolate();
    _setupFocusListeners();
    _setupSensorStream();
  }

  /// Spawns a background isolate to handle all data processing
  Future<void> _initializeBackgroundIsolate() async {
    _mainReceivePort = ReceivePort();
    try {
      _backgroundIsolate = await Isolate.spawn(
        _backgroundIsolateEntryPoint,
        _mainReceivePort!.sendPort,
      );
    } catch (e) {
      setState(() {
        liveTelemetry.insert(0, "[ERROR] Failed to spawn isolate: $e");
      });
      return;
    }

    // Listen for messages from background isolate
    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        // Receive background isolate's SendPort for two-way communication
        _isolateSendPort = message;
      } else if (message is String) {
        // Receive formatted log entries and update UI on main thread
        setState(() {
          liveTelemetry.insert(0, message);
          // Keep telemetry log bounded to prevent memory bloat
          if (liveTelemetry.length > 100) {
            liveTelemetry.removeLast();
          }
        });
        // Auto-scroll telemetry to show newest entry
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_telemetryScrollController.hasClients) {
            _telemetryScrollController.jumpTo(0);
          }
        });
      }
    });
  }

  /// Background isolate entry point (top-level function required for Isolates)
  static void _backgroundIsolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    // Send background isolate's SendPort to main isolate
    sendPort.send(receivePort.sendPort);

    int? lastTouchDownTime;

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;
        switch (type) {
          case 'touch_down':
            // Store touch down timestamp for dwell time calculation
            lastTouchDownTime = message['timestamp'] as int;
            final x = message['x'] as double;
            final y = message['y'] as double;
            sendPort.send(
                "[TOUCH_DOWN] X: ${x.toStringAsFixed(1)}, Y: ${y.toStringAsFixed(1)}");
            break;
          case 'touch_up':
            // Calculate dwell time (ms between down and up events)
            if (lastTouchDownTime != null) {
              final upTime = message['timestamp'] as int;
              final dwellTime = upTime - lastTouchDownTime!;
              sendPort.send("[TOUCH_UP] Dwell Time: ${dwellTime}ms");
              lastTouchDownTime = null;
            }
            break;
          case 'gyro':
            // Format gyroscope data for telemetry
            final x = message['x'] as double;
            final y = message['y'] as double;
            final z = message['z'] as double;
            sendPort.send(
                "[GYRO] X: ${x.toStringAsFixed(3)}, Y: ${y.toStringAsFixed(3)}, Z: ${z.toStringAsFixed(3)}");
            break;
        }
      }
    });
  }

  /// Sets up focus listeners to start/stop sensors when text fields are interacted with
  void _setupFocusListeners() {
    _usernameFocus.addListener(_handleFocusChange);
    _passwordFocus.addListener(_handleFocusChange);
  }

  /// Handles focus changes to manage sensor lifecycle (battery optimization)
  void _handleFocusChange() {
    final isAnyFieldFocused =
        _usernameFocus.hasFocus || _passwordFocus.hasFocus;
    if (isAnyFieldFocused && !isRecording) {
      _startHardwareSensors();
    } else if (!isAnyFieldFocused && isRecording) {
      _stopHardwareSensors();
    }
  }

  /// Sets up EventChannel listener for native sensor data
  void _setupSensorStream() {
    _sensorSubscription = _sensorStream.receiveBroadcastStream().listen(
      (event) {
        // Forward gyroscope data to background isolate for processing
        if (event is Map<dynamic, dynamic> && _isolateSendPort != null) {
          _isolateSendPort!.send({
            'type': 'gyro',
            'x': event['x'] as double,
            'y': event['y'] as double,
            'z': event['z'] as double,
          });
        }
      },
      onError: (error) {
        setState(() {
          liveTelemetry.insert(0, "[ERROR] Sensor stream error: $error");
        });
      },
    );
  }

  /// Invokes native MethodChannel to start gyroscope streaming
  Future<void> _startHardwareSensors() async {
    try {
      await _controlChannel.invokeMethod('start');
      setState(() {
        isRecording = true;
        liveTelemetry.insert(0, "[SYSTEM] Native Gyroscope Bridge Activated");
      });
    } on PlatformException catch (e) {
      setState(() {
        liveTelemetry.insert(0, "[ERROR] Failed to start sensors: ${e.message}");
      });
    }
  }

  /// Invokes native MethodChannel to stop gyroscope streaming
  Future<void> _stopHardwareSensors() async {
    try {
      await _controlChannel.invokeMethod('stop');
      setState(() {
        isRecording = false;
        liveTelemetry.insert(0, "[SYSTEM] Sensors Suspended (Battery Saved)");
      });
    } on PlatformException catch (e) {
      setState(() {
        liveTelemetry.insert(0, "[ERROR] Failed to stop sensors: ${e.message}");
      });
    }
  }

  /// Captures raw touch down events for dwell time calculation
  void _handlePointerDown(PointerDownEvent event) {
    _isolateSendPort?.send({
      'type': 'touch_down',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'x': event.position.dx,
      'y': event.position.dy,
    });
  }

  /// Captures raw touch up events for dwell time calculation
  void _handlePointerUp(PointerUpEvent event) {
    _isolateSendPort?.send({
      'type': 'touch_up',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void dispose() {
    // Clean up all resources to prevent memory leaks
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _sensorSubscription?.cancel();
    _backgroundIsolate?.kill(priority: Isolate.immediate);
    _mainReceivePort?.close();
    _telemetryScrollController.dispose();
    _stopHardwareSensors();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listener widget captures all raw pointer events for touch dynamics
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saila Zero-Trust Engine'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Zero-Trust Login",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isRecording ? "🔴 RECORDING BIOMETRICS" : "⚪ IDLE",
                style: TextStyle(
                  color: isRecording ? Colors.redAccent : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),

              // Username field
              TextField(
                focusNode: _usernameFocus,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),

              // Password field (obscured for security)
              TextField(
                focusNode: _passwordFocus,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),

              // Submit button (unfocuses fields to stop sensors)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    _usernameFocus.unfocus();
                    _passwordFocus.unfocus();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Login data submitted")),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("Submit"),
                ),
              ),

              const SizedBox(height: 32),
              const Text(
                "Live Telemetry Stream:",
                style: TextStyle(color: Colors.blueAccent),
              ),
              const Divider(color: Colors.blueAccent),

              // Scrolling telemetry console
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: ListView.builder(
                    controller: _telemetryScrollController,
                    itemCount: liveTelemetry.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          liveTelemetry[index],
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            color: Colors.greenAccent,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
