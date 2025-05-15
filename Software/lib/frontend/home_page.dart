import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/VolumeController.dart';
import 'package:mixlit/frontend/components/util/rate_limit_updates.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/backend/application/LEDController.dart';
import 'package:mixlit/backend/application/Updater.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:mixlit/frontend/controllers/mute_button_controller.dart';
import 'package:mixlit/frontend/controllers/connection_handler.dart';
import 'package:mixlit/frontend/controllers/device_event_handler.dart';
import 'package:mixlit/frontend/components/vertical_slider_card.dart';
import 'package:mixlit/frontend/components/application_icon.dart';
import 'package:mixlit/frontend/components/icon_colour_extractor.dart';
import 'package:mixlit/frontend/menu/slider_assignment.dart';
import 'package:window_manager/window_manager.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WindowListener, TrayListener {
  final SerialWorker _worker = SerialWorker();
  final ApplicationManager _applicationManager = ApplicationManager();
  late final MuteButtonController _muteButtonController;
  late final VolumeController _volumeController;
  late final ConnectionHandler _connectionHandler;
  late final DeviceEventHandler _deviceEventHandler;

  // App state
  final List<double> _sliderValues = List.filled(5, 0.0);
  List<ProcessVolume?> _assignedApps = List.filled(5, null);
  final Map<String, Uint8List?> _appIcons = {};
  List<String> _sliderTags = List.filled(5, 'unassigned');
  bool _configLoaded = false;

  late final RateLimitedUpdater _uiUpdater;
  late final BatchedValueUpdater<double> _sliderUpdater;

  // Colouring
  final Map<int, Color> _sliderColors = {};

  final Color _defaultAppColor = const Color.fromARGB(255, 188, 184, 147);
  final Color _deviceVolumeColor = const Color.fromARGB(255, 188, 184, 147);
  final Color _masterVolumeColor = const Color.fromARGB(255, 188, 184, 147);
  final Color _activeAppColor = const Color.fromARGB(255, 69, 205, 255);
  final Color _unassignedColor = const Color.fromARGB(255, 51, 51, 51);

  late final LEDController _ledController;
  bool _useAnimatedLEDs = false;

  @override
  void initState() {
    super.initState();
    _initTray();
    windowManager.addListener(this);

    _uiUpdater = RateLimitedUpdater(
      const Duration(milliseconds: 2),
      _performUIUpdate,
    );

    _sliderUpdater = BatchedValueUpdater<double>(
      const Duration(milliseconds: 2),
      _batchUpdateSliders,
    );

    _muteButtonController = MuteButtonController(
      buttonCount: 5,
      vsync: this,
      onVolumeAdjustment: _handleDirectVolumeAdjustment,
      onSliderValueUpdated: _updateSliderValue,
    );

    _initializeConfiguration().then((_) {
      _volumeController = VolumeController(
        applicationManager: _applicationManager,
        sliderTags: _sliderTags,
        assignedApps: _assignedApps,
      );

      _muteButtonController.setVolumeController(_volumeController);

      for (int i = 0; i < _muteButtonController.muteStates.length; i++) {
        _volumeController.updateMuteState(
            i, _muteButtonController.muteStates[i]);
      }

      _connectionHandler = ConnectionHandler();

      _deviceEventHandler = DeviceEventHandler(
        worker: _worker,
        onSliderDataReceived: _handleSliderData,
        onButtonEvent: _handleButtonEvent,
        onConnectionStateChanged: _handleConnectionStateChanged,
      );

      _ledController = LEDController(
        serialWorker: _worker,
        applicationManager: _applicationManager,
        sliderValues: _sliderValues,
        sliderTags: _sliderTags,
        appIcons: _appIcons,
        isAnimated: _useAnimatedLEDs,
      );

      _connectionHandler.initializeDeviceConnection(
          context, _worker.connectionState.first);

      _deviceEventHandler.initialize();

      setState(() {
        _configLoaded = true;
      });

      _ledController.updateAllLEDs();

      _checkForUpdates();
    });
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon('lib/frontend/assets/images/logo/app_icon.ico');
    await trayManager.setToolTip("MixLit: Application Volume Control");
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(label: "Show Window", onClick: (menuItem) => _showWindow()),
        MenuItem(label: "Close", onClick: (menuItem) => _exitApp()),
      ],
    ));
  }

  void _showWindow() {
    windowManager.show();
    windowManager.focus();
  }

  void _exitApp() {
    trayManager.destroy();
    windowManager.destroy();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onWindowClose() async {
    windowManager.hide();
  }

  Future<void> _loadIconsForAssignedApps() async {
    for (int i = 0; i < _assignedApps.length; i++) {
      final app = _assignedApps[i];
      final sliderTag = _sliderTags[i];

      if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
        _sliderColors[i] = _deviceVolumeColor;
      } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
        _sliderColors[i] = _masterVolumeColor;
      } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
        _sliderColors[i] = _activeAppColor;
      } else if (sliderTag == ConfigManager.TAG_UNASSIGNED) {
        _sliderColors[i] = _unassignedColor;
      } else if (sliderTag == ConfigManager.TAG_APP && app != null) {
        if (!_appIcons.containsKey(app.processPath)) {
          _appIcons[app.processPath] = await nativeIconToBytes(app.processPath);
        }

        if (_appIcons[app.processPath] != null) {
          _sliderColors[i] = await IconColorExtractor.extractDominantColor(
              _appIcons[app.processPath]!, app.processPath,
              defaultColor: _defaultAppColor);
        } else {
          _sliderColors[i] = _defaultAppColor;
        }
      } else {
        _sliderColors[i] = _defaultAppColor;
      }
    }
  }

  Future<void> _initializeConfiguration() async {
    await _applicationManager.configLoaded;

    setState(() {
      for (int i = 0;
          i < _sliderValues.length &&
              i < _applicationManager.sliderValues.length;
          i++) {
        _sliderValues[i] = _applicationManager.sliderValues[i];
      }

      _sliderTags =
          List.from(_applicationManager.sliderTags.take(_sliderTags.length));

      for (int i = 0;
          i < _muteButtonController.muteStates.length &&
              i < _applicationManager.muteStates.length;
          i++) {
        _muteButtonController.muteStates[i] = _applicationManager.muteStates[i];
      }

      for (int i = 0; i < _sliderTags.length; i++) {
        if (_sliderTags[i] == ConfigManager.TAG_APP) {
          _assignedApps[i] = _applicationManager.assignedApplications[i];
        } else {
          _assignedApps[i] = null;
        }
      }
    });

    await _loadIconsForAssignedApps();
  }

  void _handleSliderData(Map<int, int> data) {
    if (!_configLoaded) return;

    data.forEach((sliderId, sliderValue) {
      if (sliderId >= 0 && sliderId < _sliderValues.length) {
        _sliderUpdater.updateValue(sliderId.toString(), sliderValue.toDouble());
        _ledController.updateSliderValue(sliderId, sliderValue.toDouble());

        _muteButtonController.updatePreviousVolumeValue(
            sliderId, sliderValue.toDouble());

        if (!_muteButtonController.muteStates[sliderId]) {
          _volumeController.adjustVolume(sliderId, sliderValue.toDouble());
        } else {
          _volumeController.storeVolumeValue(sliderId, sliderValue.toDouble());
        }
      }
    });

    _uiUpdater.requestUpdate();
  }

  void _batchUpdateSliders(Map<String, double> updates) {
    updates.forEach((sliderIdStr, value) {
      final sliderId = int.parse(sliderIdStr);
      if (sliderId >= 0 && sliderId < _sliderValues.length) {
        _sliderValues[sliderId] = value;
      }
    });
  }

  void _performUIUpdate() {
    if (mounted && _configLoaded) {
      setState(() {});
    }
  }

  void _handleButtonEvent(int buttonIndex, bool isPressed, bool isReleased) {
    if (!_configLoaded) return;

    if (isPressed) {
      if (_muteButtonController.muteStates[buttonIndex]) {
        _sliderValues[buttonIndex] =
            _muteButtonController.previousVolumeValues[buttonIndex];
      } else {
        _sliderValues[buttonIndex] = MuteButtonController.muteVolume;
      }

      _muteButtonController.handleButtonDown(buttonIndex);
      _muteButtonController.checkLongPress(buttonIndex);

      _uiUpdater.requestUpdate();
    } else if (isReleased) {
      _muteButtonController.handleButtonUp(buttonIndex);
      _uiUpdater.requestUpdate();
    }
  }

  void _handleConnectionStateChanged(bool connected) {
    if (mounted) {
      _connectionHandler.showConnectionNotification(context, connected);

      if (connected && _configLoaded) {
        _initializeConfiguration();
      }
    }
  }

  void _handleVolumeAdjustment(int sliderId, double value) {
    _sliderValues[sliderId] = value;

    _ledController.updateSliderValue(sliderId, value);

    _muteButtonController.updatePreviousVolumeValue(sliderId, value);

    if (!_muteButtonController.muteStates[sliderId]) {
      final bool bypassRateLimit = value <= MuteButtonController.muteVolume;
      _volumeController.adjustVolume(sliderId, value,
          bypassRateLimit: bypassRateLimit);
    } else {
      _volumeController.storeVolumeValue(sliderId, value);
    }

    _uiUpdater.requestUpdate();
  }

  void _handleDirectVolumeAdjustment(int sliderId, double value) {
    _sliderValues[sliderId] = value;

    _volumeController.directVolumeAdjustment(sliderId, value);
    _uiUpdater.requestUpdate();
  }

  void _updateSliderValue(int sliderId, double value) {
    _sliderValues[sliderId] = value;
    _uiUpdater.requestUpdate();
  }

  void _toggleMute(int index) {
    if (!_muteButtonController.muteStates[index]) {
      _muteButtonController.previousVolumeValues[index] = _sliderValues[index];
      _volumeController.storeVolumeValue(index, _sliderValues[index]);
    }

    _muteButtonController.toggleMuteState(index);
    _uiUpdater.requestUpdate();
  }

  @override
  void dispose() {
    _uiUpdater.dispose();
    _sliderUpdater.dispose();

    _worker.dispose();
    _muteButtonController.dispose();
    if (_configLoaded) {
      _ledController.dispose();
      _deviceEventHandler.dispose();
      _volumeController.dispose();
      _connectionHandler.dispose();
    }
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _selectApp(int index) async {
    final previousAssignedApp = _assignedApps[index];
    final previousTag = _sliderTags[index];

    _assignedApps = await assignApplication(
      context,
      index,
      _applicationManager,
      _assignedApps,
      _appIcons,
      _sliderValues,
      _sliderTags,
    );

    if (previousAssignedApp != _assignedApps[index] ||
        previousTag != _sliderTags[index]) {
      await _updateSliderColor(index);
      _ledController.updateSliderLEDs(index);
    }

    setState(() {
      _volumeController.updateSliderTags(_sliderTags);
      _volumeController.updateAssignedApps(_assignedApps);
      _ledController.updateSliderTags(_sliderTags);
    });
  }

  void _toggleLEDAnimation() {
    setState(() {
      _useAnimatedLEDs = !_useAnimatedLEDs;
      _ledController.setAnimated(_useAnimatedLEDs);
    });
  }

  Future<void> _updateSliderColor(int index) async {
    final app = _assignedApps[index];
    final sliderTag = _sliderTags[index];

    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      _sliderColors[index] = _deviceVolumeColor;
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      _sliderColors[index] = _masterVolumeColor;
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      _sliderColors[index] = _activeAppColor;
    } else if (sliderTag == ConfigManager.TAG_UNASSIGNED) {
      _sliderColors[index] = _unassignedColor;
    } else if (sliderTag == ConfigManager.TAG_APP && app != null) {
      if (!_appIcons.containsKey(app.processPath) ||
          _appIcons[app.processPath] == null) {
        _appIcons[app.processPath] = await nativeIconToBytes(app.processPath);
      }

      if (_appIcons[app.processPath] != null) {
        _sliderColors[index] = await IconColorExtractor.extractDominantColor(
            _appIcons[app.processPath]!, app.processPath,
            defaultColor: _defaultAppColor);
      } else {
        _sliderColors[index] = _defaultAppColor;
      }
    } else {
      _sliderColors[index] = _defaultAppColor;
    }

    _ledController.updateSliderLEDs(index);
  }

  Future<void> _checkForUpdates() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await Updater().checkAndShowUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (!_configLoaded) {
      return Scaffold(
        backgroundColor:
            isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Loading configuration...',
                style: TextStyle(
                  fontFamily: 'BitstreamVeraSans',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF1E1E1E)
          : const Color.fromARGB(255, 214, 214, 214),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox()),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'lib/frontend/assets/images/logo/mixlit_full.png',
                        height: 60,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Volume Mixer Thingy Majig 9000',
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          fontSize: 22,
                          fontWeight: FontWeight.w100,
                          letterSpacing: 1,
                          color: isDarkMode
                              ? Colors.white
                              : const Color.fromARGB(255, 92, 92, 92),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ListenableBuilder(
                        listenable: _connectionHandler,
                        builder: (context, child) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
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
                                const SizedBox(width: 4),
                                Text(
                                  _connectionHandler.isCurrentlyConnected
                                      ? 'Connected'
                                      : 'Disconnected',
                                  style: TextStyle(
                                    fontFamily: 'BitstreamVeraSans',
                                    color:
                                        _connectionHandler.isCurrentlyConnected
                                            ? Colors.green
                                            : Colors.red,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Main content with sliders in a horizontal layout
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    final String sliderTag = _sliderTags[index];

                    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
                      iconWidget = const Icon(Icons.speaker,
                          color: Colors.white, size: 32);
                      title = 'Device';
                      primaryColor = Colors.blue;
                    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
                      iconWidget = const Icon(Icons.volume_up,
                          color: Colors.white, size: 32);
                      title = 'Master\nVolume';
                      primaryColor = Colors.green;
                    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
                      iconWidget = const Icon(Icons.app_registration,
                          color: Colors.white, size: 32);
                      title = 'Active\nApp';
                      primaryColor = Colors.purple;
                    } else if (sliderTag == ConfigManager.TAG_APP &&
                        _assignedApps[index] != null) {
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

                      primaryColor = Colors.amber;
                    } else {
                      iconWidget = const Icon(Icons.add_circle_outline,
                          color: Colors.white, size: 32);
                      title = 'N/A';
                      primaryColor = Colors.grey;
                    }

                    return VerticalSliderCard(
                      title: title,
                      iconWidget: iconWidget,
                      value:
                          _sliderValues[index] / 1024, // Normalize to 0.0-1.0
                      isMuted: isMuted,
                      isActive: sliderTag != ConfigManager.TAG_UNASSIGNED,
                      percentage: volumePercentage,
                      accentColor: _sliderColors[index] ??
                          (sliderTag == ConfigManager.TAG_APP
                              ? _defaultAppColor
                              : _unassignedColor),
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
