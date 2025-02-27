import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/menu/slider_assignment.dart';
import 'package:mixlit/frontend/components/slider_container.dart';
import 'package:mixlit/frontend/menu/dialog/warning.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:win32audio/win32audio.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SerialWorker _worker = SerialWorker(); // Updated to use SerialWorker
  final ApplicationManager _applicationManager = ApplicationManager();

  final List<double> _sliderValues = [0, 0, 0, 0, 0];
  List<ProcessVolume?> _assignedApps = [null, null, null, null, null];
  final Map<String, Uint8List?> _appIcons = {};
  final List<String> _sliderTags = [
    'unassigned',
    'unassigned',
    'unassigned',
    'unassigned',
    'unassigned'
  ];

  bool _hasShownInitialDialog = false;
  bool _isCurrentlyConnected = false;
  bool _isNotificationInProgress = false;

  void _handleVolumeAdjustment(int sliderId, double value) {
    if (_sliderTags[sliderId] == 'defaultDevice') {
      _applicationManager.adjustDeviceVolume(value);
    } else if (_sliderTags[sliderId] == 'app' &&
        _assignedApps[sliderId] != null) {
      final app = _assignedApps[sliderId];
      if (app != null) {
        _applicationManager.assignApplicationToSlider(sliderId, app);
        _applicationManager.adjustVolume(sliderId, value);
      }
    }
  }

  void _showConnectionNotification(bool connected) {
    // Prevent notification spam
    if (_isNotificationInProgress) return;
    if (connected == _isCurrentlyConnected) return;

    _isNotificationInProgress = true;
    _isCurrentlyConnected = connected;

    // Show the notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              connected ? Icons.usb_rounded : Icons.usb_off_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(connected
                ? "MixLit device connected"
                : "MixLit device disconnected"),
          ],
        ),
        backgroundColor: connected ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );

    // Reset notification flag after delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _isNotificationInProgress = false;
    });
  }

  void _initializeDeviceConnection() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check initial connection state
      final isConnected = await _worker.connectionState.first;
      if (!isConnected && !_hasShownInitialDialog) {
        _hasShownInitialDialog = true;
        if (mounted) {
          FailedToConnectToDeviceDialog.show(context,
              "Couldn't detect your MixLit, app will maintain basic functionality.");
        }
      }
    });
  }

  void _setupConnectionListener() {
    _worker.connectionState.listen(
      (connected) {
        if (mounted) {
          _showConnectionNotification(connected);
        }
      },
      onError: (error) {
        print('Connection stream error: $error');
      },
    );
  }

  void _setupSliderListener() {
    _worker.sliderData.listen(
      (data) {
        setState(() {
          data.forEach((sliderId, sliderValue) {
            if (sliderId >= 0 && sliderId < _sliderValues.length) {
              _sliderValues[sliderId] = sliderValue.toDouble();
              _handleVolumeAdjustment(sliderId, sliderValue.toDouble());
            }
          });
        });
      },
      onError: (error) {
        print('Slider stream error: $error');
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeDeviceConnection();
    _setupConnectionListener();
    _setupSliderListener();
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double containerWidth = screenWidth * 0.6;
    final double containerHeight = containerWidth * 0.6;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/frontend/assets/images/background/background.png',
            fit: BoxFit.cover,
          ),
          Center(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                SliderContainer(
                  containerWidth: containerWidth,
                  containerHeight: containerHeight,
                  sliderValues: _sliderValues,
                  assignedApps: _assignedApps,
                  appIcons: _appIcons,
                  sliderTags: _sliderTags,
                  onAssignApp: (sliderIndex) async {
                    _assignedApps = await assignApplication(
                      context,
                      sliderIndex,
                      _applicationManager,
                      _assignedApps,
                      _appIcons,
                      _sliderValues,
                      _sliderTags,
                    );
                    if (_assignedApps[sliderIndex] != null) {
                      _sliderTags[sliderIndex] = 'app';
                    }
                    setState(() {});
                  },
                  onSliderChange: (sliderIndex, value) {
                    setState(() {
                      _sliderValues[sliderIndex] = value;
                      _handleVolumeAdjustment(sliderIndex, value);
                    });
                  },
                  onSelectDefaultDevice: (sliderIndex, isDefault) {
                    setState(() {
                      _sliderTags[sliderIndex] =
                          isDefault ? 'defaultDevice' : 'unassigned';
                    });
                  },
                ),
                Positioned(
                  top: -(containerHeight * 0.25),
                  child: Image.asset(
                    'lib/frontend/assets/images/logo/mixlit_full.png',
                    height: containerHeight * 0.22,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
