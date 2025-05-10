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

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final SerialWorker _worker = SerialWorker();
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

  // Mute button
  final List<bool> _muteStates = [false, false, false, false, false];
  final List<AnimationController> _buttonAnimControllers = [];
  final List<Animation<double>> _buttonAnimations = [];

  // Button press tracking
  final List<DateTime?> _buttonPressStartTimes = [null, null, null, null, null];
  final List<bool> _isLongPressing = [false, false, false, false, false];
  final List<bool> _wasUnmutedBeforeLongPress = [
    false,
    false,
    false,
    false,
    false
  ];
  final List<double> _previousVolumeValues = [1.0, 1.0, 1.0, 1.0, 1.0];
  static const Duration _longPressDuration = Duration(milliseconds: 500);
  static const double _muteVolume = 0.0001;

  bool _hasShownInitialDialog = false;
  bool _isCurrentlyConnected = false;
  bool _isNotificationInProgress = false;

  // Adjusts the volume for either a device or an app
  void _handleVolumeAdjustment(int sliderId, double value) {
    _sliderValues[sliderId] = value;

    if (value <= _muteVolume ||
        (_muteStates[sliderId] && value == _previousVolumeValues[sliderId])) {
      _directVolumeAdjustment(sliderId, value);
    } else {
      if (_sliderTags[sliderId] == 'defaultDevice') {
        _applicationManager.adjustDeviceVolume(value);
      } else if (_sliderTags[sliderId] == 'app' &&
          _assignedApps[sliderId] != null) {
        final app = _assignedApps[sliderId];
        if (app != null) {
          _applicationManager.adjustVolume(sliderId, value);
        }
      }
    }
  }

  void _directVolumeAdjustment(int sliderId, double value) {
    if (_sliderTags[sliderId] == 'defaultDevice') {
      int volumeLevel = ((value / 1024) * 100).round();
      Audio.setVolume(volumeLevel / 100, AudioDeviceType.output);
    } else if (_sliderTags[sliderId] == 'app' &&
        _assignedApps[sliderId] != null) {
      final app = _assignedApps[sliderId];
      if (app != null) {
        double volumeLevel = value / 1024;
        if (volumeLevel <= 0.009) {
          volumeLevel = 0.0001;
        }
        Audio.setAudioMixerVolume(app.processId, volumeLevel);
      }
    }

    if (_sliderTags[sliderId] == 'defaultDevice') {
      _applicationManager.sliderValues[sliderId] = value;
    } else if (_sliderTags[sliderId] == 'app') {
      _applicationManager.sliderValues[sliderId] = value;
    }
  }

  void _muteAudio(int sliderIndex) {
    if (!_muteStates[sliderIndex]) {
      // Save the current volume before muting
      _previousVolumeValues[sliderIndex] = _sliderValues[sliderIndex];
    }

    _muteStates[sliderIndex] = true;
    _sliderValues[sliderIndex] = _muteVolume;
    _handleVolumeAdjustment(sliderIndex, _muteVolume);
    _buttonAnimControllers[sliderIndex].forward();
  }

  void _unmuteAudio(int sliderIndex) {
    _muteStates[sliderIndex] = false;
    _sliderValues[sliderIndex] = _previousVolumeValues[sliderIndex];
    _handleVolumeAdjustment(sliderIndex, _previousVolumeValues[sliderIndex]);
    _buttonAnimControllers[sliderIndex].reverse();
  }

  void _toggleMuteState(int sliderIndex) {
    setState(() {
      if (_muteStates[sliderIndex]) {
        _unmuteAudio(sliderIndex);
      } else {
        _muteAudio(sliderIndex);
      }
    });
  }

  void _handleButtonDown(int buttonIndex) {
    print('Button down: $buttonIndex');

    _buttonPressStartTimes[buttonIndex] = DateTime.now();

    setState(() {
      _wasUnmutedBeforeLongPress[buttonIndex] = !_muteStates[buttonIndex];

      if (_muteStates[buttonIndex]) {
        _unmuteAudio(buttonIndex);
      } else {
        _muteAudio(buttonIndex);
      }

      _isLongPressing[buttonIndex] = false;
    });

    Future.delayed(_longPressDuration, () {
      final pressStartTime = _buttonPressStartTimes[buttonIndex];
      if (pressStartTime != null) {
        print('Long press detected for button: $buttonIndex');
        setState(() {
          _isLongPressing[buttonIndex] = true;
        });
      }
    });
  }

  void _handleButtonUp(int buttonIndex) {
    print('Button up: $buttonIndex');

    final pressStartTime = _buttonPressStartTimes[buttonIndex];
    if (pressStartTime == null) {
      return;
    }

    final pressDuration = DateTime.now().difference(pressStartTime);
    _buttonPressStartTimes[buttonIndex] = null;

    setState(() {
      if (_isLongPressing[buttonIndex]) {
        print('Long press ended for button: $buttonIndex');
        if (_wasUnmutedBeforeLongPress[buttonIndex]) {
          if (_muteStates[buttonIndex]) {
            _unmuteAudio(buttonIndex);
          } else {
            _muteAudio(buttonIndex);
          }
        }

        _isLongPressing[buttonIndex] = false;
      }
    });
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
              // Only update slider if it's not muted
              if (!_muteStates[sliderId]) {
                _sliderValues[sliderId] = sliderValue.toDouble();
                if (_sliderTags[sliderId] == 'defaultDevice') {
                  _applicationManager
                      .adjustDeviceVolume(sliderValue.toDouble());
                } else if (_sliderTags[sliderId] == 'app' &&
                    _assignedApps[sliderId] != null) {
                  _applicationManager.adjustVolume(
                      sliderId, sliderValue.toDouble());
                }
              }
            }
          });
        });
      },
      onError: (error) {
        print('Slider stream error: $error');
      },
    );
  }

  void _setupButtonListener() {
    _worker.buttonData.listen(
      (data) {
        data.forEach((buttonId, state) {
          print('Button data received: $buttonId | $state');

          if (buttonId.length == 1 &&
              buttonId.codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
              buttonId.codeUnitAt(0) <= 'E'.codeUnitAt(0)) {
            // A-E to 0-4 (button mapping)
            final index = buttonId.codeUnitAt(0) - 'A'.codeUnitAt(0);

            print(
                'Processing button: ${buttonId} (index: $index), state: $state');

            if (state == 1) {
              _handleButtonDown(index);
            } else if (state == 0) {
              _handleButtonUp(index);
            }
          }
        });
      },
      onError: (error) {
        print('Button stream error: $error');
      },
    );
  }

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      );

      final animation = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      );

      _buttonAnimControllers.add(controller);
      _buttonAnimations.add(animation);
    }

    _initializeDeviceConnection();
    _setupConnectionListener();
    _setupSliderListener();
    _setupButtonListener();
  }

  @override
  void dispose() {
    _worker.dispose();

    // Dispose animation controllers
    for (var controller in _buttonAnimControllers) {
      controller.dispose();
    }

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
                          if (_sliderTags[sliderIndex] == 'defaultDevice') {
                            _applicationManager.adjustDeviceVolume(value);
                          } else if (_sliderTags[sliderIndex] == 'app' &&
                              _assignedApps[sliderIndex] != null) {
                            _applicationManager.adjustVolume(
                                sliderIndex, value);
                          }
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
                Container(
                  width: containerWidth,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (index) {
                      return AnimatedBuilder(
                          animation: _buttonAnimations[index],
                          builder: (context, child) {
                            final Color baseColor = _muteStates[index]
                                ? const Color(0xFFFF5252)
                                : const Color(0xFF4CAF50);

                            return GestureDetector(
                              onTapDown: (_) => _handleButtonDown(index),
                              onTapUp: (_) => _handleButtonUp(index),
                              onTapCancel: () {
                                // Handle case where tap is canceled
                                if (_buttonPressStartTimes[index] != null &&
                                    _isLongPressing[index]) {
                                  // If this was a long press, restore original state on cancel
                                  setState(() {
                                    if (_wasUnmutedBeforeLongPress[index]) {
                                      // Since we toggled on press down, we need to toggle again to restore
                                      if (_muteStates[index]) {
                                        _unmuteAudio(index);
                                      } else {
                                        _muteAudio(index);
                                      }
                                    }
                                    _isLongPressing[index] = false;
                                  });
                                }
                                _buttonPressStartTimes[index] = null;
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    baseColor,
                                    Colors.white,
                                    _buttonAnimations[index].value * 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: baseColor.withOpacity(0.5),
                                      spreadRadius:
                                          _buttonAnimations[index].value * 5,
                                      blurRadius: 7,
                                    ),
                                  ],
                                ),
                                transform: Matrix4.identity()
                                  ..scale(1.0 -
                                      (_buttonAnimations[index].value * 0.1)),
                                child: Center(
                                  child: Icon(
                                    _muteStates[index]
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            );
                          });
                    }),
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
