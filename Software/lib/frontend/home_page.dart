import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/menu/slider_assignment.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/frontend/controllers/mute_button_controller.dart';
import 'package:mixlit/frontend/controllers/volume_controller.dart';
import 'package:mixlit/frontend/controllers/connection_handler.dart';
import 'package:mixlit/frontend/controllers/device_event_handler.dart';
import 'package:mixlit/frontend/components/vertical_slider_card.dart';
import 'package:mixlit/frontend/components/application_icon.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final SerialWorker _worker = SerialWorker();
  final ApplicationManager _applicationManager = ApplicationManager();
  late final MuteButtonController _muteButtonController;
  late final VolumeController _volumeController;
  late final ConnectionHandler _connectionHandler;
  late final DeviceEventHandler _deviceEventHandler;

  // App state
  final List<double> _sliderValues = List.filled(5, 0.5);
  List<ProcessVolume?> _assignedApps = List.filled(5, null);
  final Map<String, Uint8List?> _appIcons = {};
  final List<String> _sliderTags = List.filled(5, 'unassigned');

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    _muteButtonController = MuteButtonController(
      buttonCount: 5,
      vsync: this,
      onVolumeAdjustment: _handleDirectVolumeAdjustment,
      onSliderValueUpdated: _updateSliderValue,
    );

    _volumeController = VolumeController(
      applicationManager: _applicationManager,
      sliderTags: _sliderTags,
      assignedApps: _assignedApps,
    );

    _connectionHandler = ConnectionHandler();

    _deviceEventHandler = DeviceEventHandler(
      worker: _worker,
      onSliderDataReceived: _handleSliderData,
      onButtonEvent: _handleButtonEvent,
      onConnectionStateChanged: _handleConnectionStateChanged,
    );

    // Initialize device connection
    _connectionHandler.initializeDeviceConnection(
        context, _worker.connectionState.first);

    // Set up event handlers
    _deviceEventHandler.initialize();
  }

  void _handleSliderData(Map<int, int> data) {
    setState(() {
      data.forEach((sliderId, sliderValue) {
        if (sliderId >= 0 && sliderId < _sliderValues.length) {
          // Only update slider if it's not muted
          if (!_muteButtonController.muteStates[sliderId]) {
            // Always use rate-limited approach for hardware slider movements
            _sliderValues[sliderId] = sliderValue.toDouble();
            _volumeController.adjustVolume(sliderId, sliderValue.toDouble());
          }
        }
      });
    });
  }

  void _handleButtonEvent(int buttonIndex, bool isPressed, bool isReleased) {
    if (isPressed) {
      // First update the UI immediately
      if (_muteButtonController.muteStates[buttonIndex]) {
        // If currently muted, update to previous value immediately
        _sliderValues[buttonIndex] =
            _muteButtonController.previousVolumeValues[buttonIndex];
      } else {
        // If currently unmuted, update to mute value immediately
        _sliderValues[buttonIndex] = MuteButtonController.muteVolume;
      }
      // Force a rapid refresh without going through setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });

      // Then handle the actual button press logic
      _muteButtonController.handleButtonDown(buttonIndex);
      setState(() {});
      _muteButtonController.checkLongPress(buttonIndex);
    } else if (isReleased) {
      _muteButtonController.handleButtonUp(buttonIndex);
      setState(() {});
    }
  }

  void _handleConnectionStateChanged(bool connected) {
    if (mounted) {
      _connectionHandler.showConnectionNotification(context, connected);
    }
  }

  void _handleVolumeAdjustment(int sliderId, double value) {
    // Store the current value in the slider values array
    setState(() {
      _sliderValues[sliderId] = value;
    });

    // Always bypass rate limiting for mute/unmute operations
    final bool bypassRateLimit = value <= MuteButtonController.muteVolume ||
        _muteButtonController.muteStates[sliderId];

    // Use the volume controller with appropriate bypass flag
    _volumeController.adjustVolume(sliderId, value,
        bypassRateLimit: bypassRateLimit);
  }

  void _handleDirectVolumeAdjustment(int sliderId, double value) {
    // Directly update UI state first for immediate feedback
    setState(() {
      _sliderValues[sliderId] = value;
    });

    // Then make the actual adjustment
    _volumeController.directVolumeAdjustment(sliderId, value);
  }

  // Direct UI update for slider values without going through the volume adjustment path
  void _updateSliderValue(int sliderId, double value) {
    // First update the internal value for immediate UI refresh
    _sliderValues[sliderId] = value;

    // Then force a state update with minimal rebuild scope
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleMute(int index) {
    _muteButtonController.toggleMuteState(index);
    setState(() {});
  }

  @override
  void dispose() {
    _worker.dispose();
    _muteButtonController.dispose();
    _deviceEventHandler.dispose();
    super.dispose();
  }

  Future<void> _selectApp(int index) async {
    _assignedApps = await assignApplication(
      context,
      index,
      _applicationManager,
      _assignedApps,
      _appIcons,
      _sliderValues,
      _sliderTags,
    );
    if (_assignedApps[index] != null) {
      _sliderTags[index] = 'app';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App header with logo and connection status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'lib/frontend/assets/images/logo/mixlit_full.png',
                        height: 40,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Volume Mixer Thingy Majig 9000',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: isDarkMode
                              ? Colors.white
                              : const Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),

                  // Connection status indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _connectionHandler.isCurrentlyConnected
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _connectionHandler.isCurrentlyConnected
                            ? Colors.green.withOpacity(0.3)
                            : Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _connectionHandler.isCurrentlyConnected
                              ? Icons.usb_rounded
                              : Icons.usb_off_rounded,
                          color: _connectionHandler.isCurrentlyConnected
                              ? Colors.green
                              : Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _connectionHandler.isCurrentlyConnected
                              ? 'MixLit Connected'
                              : 'MixLit Disconnected',
                          style: TextStyle(
                            color: _connectionHandler.isCurrentlyConnected
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Main content with sliders in a horizontal layout
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final bool isMuted =
                        _muteButtonController.muteStates[index];
                    final int volumePercentage =
                        (_sliderValues[index] / 1024 * 100).round();

                    // Determine icon, title and colors based on assignment
                    Widget? iconWidget;
                    String title;
                    Color primaryColor;

                    if (_sliderTags[index] == 'defaultDevice') {
                      iconWidget = const Icon(Icons.speaker,
                          color: Colors.white, size: 32);
                      title = 'Device\nVolume';
                      primaryColor = Colors.blue;
                    } else if (_assignedApps[index] != null) {
                      final appPath = _assignedApps[index]!.processPath;
                      if (_appIcons.containsKey(appPath) &&
                          _appIcons[appPath] != null) {
                        iconWidget =
                            ApplicationIcon(iconData: _appIcons[appPath]!);
                      } else {
                        iconWidget = const Icon(Icons.apps,
                            color: Colors.white, size: 32);
                      }

                      final appName =
                          _assignedApps[index]!.processPath.split(r'\').last;
                      title = appName.replaceAll('.exe', '');
                      // Capitalize first letter
                      title = title[0].toUpperCase() + title.substring(1);

                      primaryColor = Colors.green;
                    } else {
                      iconWidget = const Icon(Icons.add_circle_outline,
                          color: Colors.white, size: 32);
                      title = 'Assign\nApp';
                      primaryColor = Colors.grey;
                    }

                    // Make master volume card special
                    if (index == 0) {
                      title = 'Master\nVolume';
                      primaryColor = Colors.white;
                    }

                    return VerticalSliderCard(
                      title: title,
                      iconWidget: iconWidget,
                      value:
                          _sliderValues[index] / 1024, // Normalize to 0.0-1.0
                      isMuted: isMuted,
                      isActive: _sliderTags[index] != 'unassigned',
                      percentage: volumePercentage,
                      accentColor: primaryColor,
                      onSliderChanged: (value) {
                        final scaledValue =
                            value * 1024; // Scale back to original range
                        _handleVolumeAdjustment(index, scaledValue);
                      },
                      onMutePressed: () => _toggleMute(index),
                      onTap: () => _selectApp(index),
                      isDarkMode: isDarkMode,
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
