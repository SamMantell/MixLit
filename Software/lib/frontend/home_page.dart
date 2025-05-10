import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/components/MuteButtonContainer.dart';
import 'package:mixlit/frontend/menu/slider_assignment.dart';
import 'package:mixlit/frontend/components/slider_container.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/frontend/controllers/mute_button_controller.dart';
import 'package:mixlit/frontend/controllers/volume_controller.dart';
import 'package:mixlit/frontend/controllers/connection_handler.dart';
import 'package:mixlit/frontend/controllers/device_event_handler.dart';

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

  final List<double> _sliderValues = List.filled(5, 0.5);
  List<ProcessVolume?> _assignedApps = List.filled(5, null);
  final Map<String, Uint8List?> _appIcons = {};
  final List<String> _sliderTags = List.filled(5, 'unassigned');

  @override
  void initState() {
    super.initState();

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
          if (!_muteButtonController.muteStates[sliderId]) {
            _sliderValues[sliderId] = sliderValue.toDouble();
            _volumeController.adjustVolume(sliderId, sliderValue.toDouble());
          }
        }
      });
    });
  }

  void _handleButtonEvent(int buttonIndex, bool isPressed, bool isReleased) {
    if (isPressed) {
      if (_muteButtonController.muteStates[buttonIndex]) {
        _sliderValues[buttonIndex] =
            _muteButtonController.previousVolumeValues[buttonIndex];
      } else {
        _sliderValues[buttonIndex] = MuteButtonController.muteVolume;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });

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
    setState(() {
      _sliderValues[sliderId] = value;
    });

    final bool bypassRateLimit = value <= MuteButtonController.muteVolume ||
        _muteButtonController.muteStates[sliderId];

    _volumeController.adjustVolume(sliderId, value,
        bypassRateLimit: bypassRateLimit);
  }

  void _handleDirectVolumeAdjustment(int sliderId, double value) {
    _volumeController.directVolumeAdjustment(sliderId, value);
  }

  void _updateSliderValue(int sliderId, double value) {
    _sliderValues[sliderId] = value;

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _worker.dispose();
    _muteButtonController.dispose();
    _deviceEventHandler.dispose();
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
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
                      muteStates: _muteButtonController.muteStates,
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

                // Add Mute Buttons Container below slider container
                const SizedBox(height: 20),
                MuteButtonContainer(
                  containerWidth: containerWidth,
                  muteStates: _muteButtonController.muteStates,
                  buttonAnimations: _muteButtonController.buttonAnimations,
                  sliderTags: _sliderTags,
                  onTapDown: (index) {
                    _muteButtonController.handleButtonDown(index);
                    _muteButtonController.checkLongPress(index);
                    setState(() {});
                  },
                  onTapUp: (index) {
                    _muteButtonController.handleButtonUp(index);
                    setState(() {});
                  },
                  onTapCancel: (index) {
                    // Handle case where tap is canceled
                    if (_muteButtonController.buttonPressStartTimes[index] !=
                            null &&
                        _muteButtonController.isLongPressing[index]) {
                      // If this was a long press, restore original state on cancel
                      setState(() {
                        if (_muteButtonController
                            .wasUnmutedBeforeLongPress[index]) {
                          if (_muteButtonController.muteStates[index]) {
                            _muteButtonController.unmuteAudio(index);
                          } else {
                            _muteButtonController.muteAudio(index);
                          }
                        }
                        _muteButtonController.isLongPressing[index] = false;
                      });
                    }
                    _muteButtonController.buttonPressStartTimes[index] = null;
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
