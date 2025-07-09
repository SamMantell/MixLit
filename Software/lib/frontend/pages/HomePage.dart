import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/audio/VolumeController.dart';
import 'package:mixlit/frontend/components/util/rate_limit_updates.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32audio/win32audio.dart';
//import 'package:mixlit/backend/application/LEDController.dart';
import 'package:mixlit/backend/Updater.dart';
import 'package:mixlit/backend/application/serial/SerialWorker.dart';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/frontend/menus/SettingsMenu.dart';
import 'package:mixlit/backend/application/audio/MuteState.dart';
import 'package:mixlit/frontend/controllers/connection_handler.dart';
import 'package:mixlit/frontend/controllers/device_event_handler.dart';
import 'package:mixlit/frontend/components/VerticalSliderCard.dart';
import 'package:mixlit/frontend/components/HorizontalDialCard.dart';
import 'package:mixlit/frontend/components/application_icon.dart';
import 'package:mixlit/backend/application/util/IconColourExtractor.dart';
import 'package:mixlit/frontend/menus/AssignApplicationMenu.dart';
import 'package:mixlit/frontend/Theme.dart'; // Import the theme
import 'package:window_manager/window_manager.dart';

class HomePage extends StatefulWidget {
  final bool isAutoStarted;
  final Function(bool)? onThemeChanged;

  const HomePage(
      {super.key,
      this.isAutoStarted = false,
      this.onThemeChanged,
      required Future<void> Function() onSettingsChanged});

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
  StreamSubscription? _initialHardwareValuesSubscription;

  final List<double> _sliderValues = List.filled(8, 0.1);
  List<ProcessVolume?> _assignedApps = List.filled(8, null);
  final Map<String, Uint8List?> _appIcons = {};
  final Map<String, Uint8List?> _cachedAppIcons = {};
  List<String> _sliderTags = List.filled(8, 'unassigned');
  bool _configLoaded = false;

  late final RateLimitedUpdater _uiUpdater;
  late final BatchedValueUpdater<double> _sliderUpdater;

  final Map<int, Color> _sliderColors = {};

  final Map<int, AnimationController> _pulseControllers = {};
  final Map<int, Animation<double>> _pulseAnimations = {};

  //late final LEDController _ledController;
  //bool _useAnimatedLEDs = false;

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
      buttonCount: 8,
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

      _applicationManager.onAppRestored = (int sliderIndex, ProcessVolume app) {
        _assignedApps[sliderIndex] = app;

        _volumeController.updateAssignedApps(_assignedApps);

        _volumeController.updateSliderTags(_sliderTags);

        if (mounted) {
          setState(() {});
        }

        print('Synced restored app: ${app.processPath} on slider $sliderIndex');
      };

      _connectionHandler = ConnectionHandler();

      _deviceEventHandler = DeviceEventHandler(
        worker: _worker,
        onSliderDataReceived: _handleSliderData,
        onButtonEvent: _handleButtonEvent,
        onConnectionStateChanged: _handleConnectionStateChanged,
      );

      _deviceEventHandler.initialize();

      _connectionHandler.initializeDeviceConnection(
          context, _worker.connectionState.first);

      _deviceEventHandler.initialize();

      setState(() {
        _configLoaded = true;
      });

      _checkForUpdates();

      _startPeriodicUIUpdates();
    });

    _debugPrintSerialData();
  }

  void _startPeriodicUIUpdates() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && _configLoaded) {
        _updateSliderStatesFromApplicationManager();
      }
    });
  }

  void _createPulseAnimation(int sliderIndex) {
    if (_pulseControllers.containsKey(sliderIndex)) return;

    final controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    final animation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    ));

    _pulseControllers[sliderIndex] = controller;
    _pulseAnimations[sliderIndex] = animation;

    animation.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    controller.repeat(reverse: true);
  }

  void _disposePulseAnimation(int sliderIndex) {
    _pulseControllers[sliderIndex]?.dispose();
    _pulseControllers.remove(sliderIndex);
    _pulseAnimations.remove(sliderIndex);
  }

  void _updateSliderStatesFromApplicationManager() {
    bool needsUpdate = false;

    for (int i = 0; i < _sliderTags.length; i++) {
      if (_sliderTags[i] == ConfigManager.TAG_APP) {
        final currentApp = _assignedApps[i];
        final managerApp = _applicationManager.assignedApplications[i];
        final hasMissingApp =
            _applicationManager.missingApplications.containsKey(i);

        if ((currentApp == null && managerApp != null) ||
            (currentApp != null && managerApp == null)) {
          _assignedApps[i] = managerApp;
          needsUpdate = true;

          if (managerApp != null) {
            _disposePulseAnimation(i);
            _loadIconForApp(managerApp.processPath);
          }
        }

        if (hasMissingApp && !_pulseControllers.containsKey(i)) {
          _createPulseAnimation(i);
          needsUpdate = true;
        } else if (!hasMissingApp && _pulseControllers.containsKey(i)) {
          _disposePulseAnimation(i);
          needsUpdate = true;
        }
      }
    }

    if (needsUpdate) {
      _loadIconsForAssignedApps().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
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
    final minimizeToTray = await SettingsManager.getMinimizeToTray();

    if (minimizeToTray) {
      windowManager.hide();
    } else {
      _exitApp();
    }
  }

  Future<void> _loadIconForApp(String processPath) async {
    if (!_appIcons.containsKey(processPath)) {
      _appIcons[processPath] = await nativeIconToBytes(processPath);
    }
  }

  Future<Uint8List?> _loadCachedIcon(String cachedIconPath) async {
    try {
      if (await File(cachedIconPath).exists()) {
        return await File(cachedIconPath).readAsBytes();
      }
    } catch (e) {
      print('Error loading cached icon: $e');
    }
    return null;
  }

  Future<void> _loadIconsForAssignedApps() async {
    for (int i = 0; i < _assignedApps.length; i++) {
      final app = _assignedApps[i];
      final sliderTag = _sliderTags[i];

      if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
        _sliderColors[i] = AppTheme.deviceVolumeColor;
      } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
        _sliderColors[i] = AppTheme.masterVolumeColor;
      } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
        _sliderColors[i] = AppTheme.activeAppColor;
      } else if (sliderTag == ConfigManager.TAG_UNASSIGNED) {
        _sliderColors[i] = AppTheme.unassignedColor;
      } else if (sliderTag == ConfigManager.TAG_APP) {
        if (app != null) {
          await _loadIconForApp(app.processPath);

          if (_appIcons[app.processPath] != null) {
            _sliderColors[i] = await IconColorExtractor.extractDominantColor(
                _appIcons[app.processPath]!, app.processPath,
                defaultColor: AppTheme.defaultAppColor);
          } else {
            _sliderColors[i] = AppTheme.defaultAppColor;
          }
        } else {
          final missingApp = _applicationManager.missingApplications[i];
          if (missingApp != null) {
            _sliderColors[i] = AppTheme.missingAppColor;

            if (missingApp.cachedIconPath != null) {
              final cachedIcon =
                  await _loadCachedIcon(missingApp.cachedIconPath!);
              if (cachedIcon != null) {
                _cachedAppIcons[missingApp.processName] = cachedIcon;

                _sliderColors[i] =
                    await IconColorExtractor.extractDominantColor(
                        cachedIcon, missingApp.processName,
                        defaultColor: AppTheme.missingAppColor);
              }
            }
          } else {
            _sliderColors[i] = AppTheme.defaultAppColor;
          }
        }
      } else {
        _sliderColors[i] = AppTheme.defaultAppColor;
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

    _applicationManager.enableVolumeRestorationForUserAction();

    data.forEach((sliderId, sliderValue) {
      if (sliderId >= 0 && sliderId < _sliderValues.length) {
        _sliderUpdater.updateValue(sliderId.toString(), sliderValue.toDouble());

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
        _applicationManager.enableVolumeRestorationOnDeviceConnect();

        _initializeConfiguration().then((_) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (_worker.isDeviceConnected && mounted) {
              print('Requesting initial hardware values after connection...');
              _worker.requestInitialHardwareValues().then((values) {
                if (values != null && mounted) {
                  _restoreHardwareValues(values);
                }
              });
            }
          });
        });
      }
    }
  }

  void _handleVolumeAdjustment(int sliderId, double value) {
    _applicationManager.enableVolumeRestorationForUserAction();

    _sliderValues[sliderId] = value;

    _muteButtonController.updatePreviousVolumeValue(sliderId, value);

    if (!_muteButtonController.muteStates[sliderId]) {
      final bool bypassRateLimit = value <= MuteButtonController.muteVolume;
      _volumeController.adjustVolume(sliderId, value,
          bypassRateLimit: bypassRateLimit);
    } else {
      _volumeController.storeVolumeValue(sliderId, value);
    }

    _applicationManager.updateSliderConfig(
        sliderId, value, _muteButtonController.muteStates[sliderId]);

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
    _applicationManager.enableVolumeRestorationForUserAction();

    if (!_muteButtonController.muteStates[index]) {
      _muteButtonController.previousVolumeValues[index] = _sliderValues[index];
      _volumeController.storeVolumeValue(index, _sliderValues[index]);
    }

    _muteButtonController.toggleMuteState(index);

    _applicationManager.updateSliderConfig(
        index, _sliderValues[index], _muteButtonController.muteStates[index]);

    _uiUpdater.requestUpdate();
  }

  void _restoreHardwareValues(Map<int, int> hardwareValues) {
    if (!_configLoaded) return;

    print('Restoring hardware values from device: $hardwareValues');

    hardwareValues.forEach((sliderId, hardwareValue) {
      if (sliderId >= 0 && sliderId < _sliderValues.length) {
        final doubleValue = hardwareValue.toDouble();
        _sliderValues[sliderId] = doubleValue;

        _muteButtonController.updatePreviousVolumeValue(sliderId, doubleValue);

        if (!_muteButtonController.muteStates[sliderId]) {
          _volumeController.adjustVolume(sliderId, doubleValue);
        } else {
          _volumeController.storeVolumeValue(sliderId, doubleValue);
        }

        _applicationManager.updateSliderConfig(
            sliderId, doubleValue, _muteButtonController.muteStates[sliderId]);

        print('Restored slider $sliderId to hardware value: $hardwareValue');
      }
    });

    _uiUpdater.requestUpdate();
  }

  @override
  void dispose() {
    for (final controller in _pulseControllers.values) {
      controller.dispose();
    }
    _pulseControllers.clear();
    _pulseAnimations.clear();

    _uiUpdater.dispose();
    _sliderUpdater.dispose();
    _initialHardwareValuesSubscription?.cancel();

    _worker.dispose();
    _muteButtonController.dispose();
    if (_configLoaded) {
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
    }

    _initialHardwareValuesSubscription =
        _worker.initialHardwareValues.listen((hardwareValues) {
      print('Received initial hardware values in HomePage: $hardwareValues');
      _restoreHardwareValues(hardwareValues);
    });

    setState(() {
      _volumeController.updateSliderTags(_sliderTags);
      _volumeController.updateAssignedApps(_assignedApps);
      _configLoaded = true;
    });
  }

  Future<void> _updateSliderColor(int index) async {
    final app = _assignedApps[index];
    final sliderTag = _sliderTags[index];

    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      _sliderColors[index] = AppTheme.deviceVolumeColor;
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      _sliderColors[index] = AppTheme.masterVolumeColor;
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      _sliderColors[index] = AppTheme.activeAppColor;
    } else if (sliderTag == ConfigManager.TAG_UNASSIGNED) {
      _sliderColors[index] = AppTheme.unassignedColor;
    } else if (sliderTag == ConfigManager.TAG_APP) {
      if (app != null) {
        await _loadIconForApp(app.processPath);

        if (_appIcons[app.processPath] != null) {
          _sliderColors[index] = await IconColorExtractor.extractDominantColor(
              _appIcons[app.processPath]!, app.processPath,
              defaultColor: AppTheme.defaultAppColor);
        } else {
          _sliderColors[index] = AppTheme.defaultAppColor;
        }
      } else {
        final missingApp = _applicationManager.missingApplications[index];
        if (missingApp != null) {
          _sliderColors[index] = AppTheme.missingAppColor;
        } else {
          _sliderColors[index] = AppTheme.defaultAppColor;
        }
      }
    } else {
      _sliderColors[index] = AppTheme.defaultAppColor;
    }
  }

  Widget _buildSliderIcon(int index) {
    final sliderTag = _sliderTags[index];
    final app = _assignedApps[index];
    final hasMissingApp =
        _applicationManager.missingApplications.containsKey(index);

    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      return Icon(Icons.speaker,
          color: Colors.white, size: AppTheme.iconSizeLarge);
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      return Icon(Icons.volume_up,
          color: Colors.white, size: AppTheme.iconSizeLarge);
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      return Icon(Icons.app_registration,
          color: Colors.white, size: AppTheme.iconSizeLarge);
    } else if (sliderTag == ConfigManager.TAG_APP) {
      if (app != null) {
        final appPath = app.processPath;
        if (_appIcons.containsKey(appPath) && _appIcons[appPath] != null) {
          return ApplicationIcon(iconData: _appIcons[appPath]!);
        }
      } else if (hasMissingApp) {
        final missingApp = _applicationManager.missingApplications[index]!;
        final cachedIcon = _cachedAppIcons[missingApp.processName];
        if (cachedIcon != null) {
          return ApplicationIcon(iconData: cachedIcon);
        }
      }

      return Icon(Icons.apps,
          color: Colors.white, size: AppTheme.iconSizeLarge);
    } else {
      return Icon(Icons.add_circle_outline,
          color: Colors.white, size: AppTheme.iconSizeLarge);
    }
  }

  Widget _buildDialIcon(int index) {
    final sliderTag = _sliderTags[index];
    final app = _assignedApps[index];
    final hasMissingApp =
        _applicationManager.missingApplications.containsKey(index);

    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      return Icon(Icons.speaker,
          color: Colors.white, size: AppTheme.iconSizeMedium);
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      return Icon(Icons.volume_up,
          color: Colors.white, size: AppTheme.iconSizeMedium);
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      return Icon(Icons.app_registration,
          color: Colors.white, size: AppTheme.iconSizeMedium);
    } else if (sliderTag == ConfigManager.TAG_APP) {
      if (app != null) {
        final appPath = app.processPath;
        if (_appIcons.containsKey(appPath) && _appIcons[appPath] != null) {
          return ApplicationIcon(iconData: _appIcons[appPath]!);
        }
      } else if (hasMissingApp) {
        final missingApp = _applicationManager.missingApplications[index]!;
        final cachedIcon = _cachedAppIcons[missingApp.processName];
        if (cachedIcon != null) {
          return ApplicationIcon(iconData: cachedIcon);
        }
      }

      return Icon(Icons.apps,
          color: Colors.white, size: AppTheme.iconSizeMedium);
    } else {
      return Icon(Icons.add_circle_outline,
          color: Colors.white, size: AppTheme.iconSizeMedium);
    }
  }

  String _buildSliderTitle(int index) {
    final sliderTag = _sliderTags[index];
    final app = _assignedApps[index];

    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      return 'Device';
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      return 'Master\nVolume';
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      return 'Active\nApp';
    } else if (sliderTag == ConfigManager.TAG_APP) {
      if (app != null) {
        final appName = app.processPath.split(r'\').last;
        String title = appName.replaceAll('.exe', '');
        title = title[0].toUpperCase() + title.substring(1);
        return title;
      } else {
        final missingApp = _applicationManager.missingApplications[index];
        if (missingApp != null) {
          return missingApp.displayName;
        }
      }
    }

    return 'N/A';
  }

  String _buildDialTitle(int index) {
    final sliderTag = _sliderTags[index];
    final app = _assignedApps[index];

    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      return 'Device';
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      return 'Master Volume';
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      return 'Active App';
    } else if (sliderTag == ConfigManager.TAG_APP) {
      if (app != null) {
        final appName = app.processPath.split(r'\').last;
        String title = appName.replaceAll('.exe', '');
        title = title[0].toUpperCase() + title.substring(1);
        return title;
      } else {
        final missingApp = _applicationManager.missingApplications[index];
        if (missingApp != null) {
          return missingApp.displayName;
        }
      }
    }

    return 'N/A';
  }

  bool _isSliderActive(int index) {
    final sliderTag = _sliderTags[index];
    if (sliderTag == ConfigManager.TAG_UNASSIGNED) return false;

    if (sliderTag == ConfigManager.TAG_APP) {
      return _assignedApps[index] != null ||
          _applicationManager.missingApplications.containsKey(index);
    }

    return true;
  }

  Future<void> _checkForUpdates() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await Updater().checkAndShowUpdateDialog(context);
  }

  void _onSettingsPressed() async {
    await showSettingsDialog(
      context,
      rawDataStream: _worker.rawData,
      sliderDataStream: _worker.sliderData,
      buttonDataStream: _worker.buttonData,
      onThemeChanged: widget.onThemeChanged,
    );
  }

  void _debugPrintSerialData() {
    _worker.rawData.listen((data) {
      print('HomePage - Raw data: $data');
    });

    _worker.sliderData.listen((data) {
      print('HomePage - Slider data: $data');
    });

    _worker.buttonData.listen((data) {
      print('HomePage - Button data: $data');
    });
  }

  void _onClosePressed() {
    windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (!_configLoaded) {
      return DragToMoveArea(
        child: Scaffold(
          backgroundColor: AppTheme.getBackgroundColor(isDarkMode),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                SizedBox(height: AppTheme.spacingLarge),
                Text(
                  'Loading configuration...',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.getPrimaryTextColor(isDarkMode),
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DragToMoveArea(
      child: Scaffold(
        backgroundColor: AppTheme.getSecondaryBackgroundColor(isDarkMode),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 150),

                        //logo & title
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset(
                                'lib/frontend/assets/images/logo/mixlit_full.png',
                                height: AppTheme.iconSizeXLarge,
                                fit: BoxFit.contain,
                              ),
                              SizedBox(height: AppTheme.spacingSmall),
                              Text(
                                'Volume Mixer Thingy Majig 9000',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: AppTheme.getPrimaryTextColor(
                                          isDarkMode),
                                    ),
                              ),
                            ],
                          ),
                        ),

                        //Settings & close button
                        SizedBox(
                          width: 150,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                //Settings button
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _onSettingsPressed,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.borderRadiusLarge),
                                    child: Container(
                                      padding:
                                          EdgeInsets.all(AppTheme.spacingSmall),
                                      decoration: AppTheme.getButtonDecoration(
                                          isDarkMode),
                                      child: Icon(
                                        Icons.settings,
                                        color: AppTheme.getPrimaryTextColor(
                                                isDarkMode)
                                            .withOpacity(
                                                AppTheme.opacityAlmostOpaque),
                                        size: AppTheme.iconSizeMedium,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: AppTheme.spacingSmall),
                                //Close button
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _onClosePressed,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.borderRadiusLarge),
                                    child: Container(
                                      padding:
                                          EdgeInsets.all(AppTheme.spacingSmall),
                                      decoration: AppTheme.getButtonDecoration(
                                          isDarkMode,
                                          isDestructive: true),
                                      child: Icon(
                                        Icons.close,
                                        color: AppTheme.errorColor.withOpacity(
                                            AppTheme.opacityAlmostOpaque),
                                        size: AppTheme.iconSizeMedium,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    //connection status indicator
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ListenableBuilder(
                          listenable: _connectionHandler,
                          builder: (context, child) {
                            final isConnected =
                                _connectionHandler.isCurrentlyConnected;
                            return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: AppTheme.spacingMedium,
                                  vertical: AppTheme.spacingSmall),
                              decoration: AppTheme.getStatusIndicatorDecoration(
                                  isConnected, isDarkMode),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isConnected
                                        ? Icons.usb_rounded
                                        : Icons.usb_off_rounded,
                                    color: AppTheme.getConnectionColor(
                                        isConnected),
                                    size: AppTheme.iconSizeSmall,
                                  ),
                                  SizedBox(width: AppTheme.spacingXSmall),
                                  Text(
                                    isConnected ? 'Connected' : 'Disconnected',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppTheme.getConnectionColor(
                                              isConnected),
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

                SizedBox(height: AppTheme.spacingLarge),

                //dial cards
                SizedBox(
                  height: AppTheme.dialCardHeight,
                  child: Row(
                    children: List.generate(3, (index) {
                      final dialIndex = index +
                          5; //TODO: Indices 5, 6, 7 for dials - make dynamic instead (firmware update needed)
                      final int volumePercentage =
                          (_sliderValues[dialIndex] / 1024 * 100).round();

                      final Widget iconWidget = _buildDialIcon(dialIndex);
                      final String title = _buildDialTitle(dialIndex);
                      final bool isActive = _isSliderActive(dialIndex);
                      final bool hasMissingApp = _applicationManager
                          .missingApplications
                          .containsKey(dialIndex);

                      Color primaryColor;
                      final sliderTag = _sliderTags[dialIndex];

                      if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
                        primaryColor = AppTheme.deviceSliderColor;
                      } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
                        primaryColor = AppTheme.masterSliderColor;
                      } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
                        primaryColor = AppTheme.activeSliderColor;
                      } else if (sliderTag == ConfigManager.TAG_APP) {
                        if (_assignedApps[dialIndex] != null) {
                          primaryColor = AppTheme.appSliderColor;
                        } else if (hasMissingApp) {
                          primaryColor = AppTheme.missingAppColor;
                        } else {
                          primaryColor = AppTheme.unassignedSliderColor;
                        }
                      } else {
                        primaryColor = AppTheme.unassignedSliderColor;
                      }

                      return Expanded(
                        child: HorizontalDialCard(
                          title: title,
                          iconWidget: iconWidget,
                          value: _sliderValues[dialIndex] / 1024,
                          isActive: isActive,
                          percentage: volumePercentage,
                          accentColor: hasMissingApp
                              ? AppTheme.missingAppColor
                              : (_sliderColors[dialIndex] ?? primaryColor),
                          accentOpacity: hasMissingApp &&
                                  _pulseAnimations.containsKey(dialIndex)
                              ? _pulseAnimations[dialIndex]!.value
                              : 1.0,
                          onDialChanged: (value) {
                            final scaledValue = value * 1024;
                            _handleVolumeAdjustment(dialIndex, scaledValue);
                          },
                          onTap: () => _selectApp(dialIndex),
                          isDarkMode: isDarkMode,
                        ),
                      );
                    }),
                  ),
                ),

                SizedBox(height: AppTheme.spacingMedium),

                //Vertical sliders
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final bool isMuted =
                          _muteButtonController.muteStates[index];
                      final int volumePercentage =
                          (_sliderValues[index] / 1024 * 100).round();

                      final Widget iconWidget = _buildSliderIcon(index);
                      final String title = _buildSliderTitle(index);
                      final bool isActive = _isSliderActive(index);
                      final bool hasMissingApp = _applicationManager
                          .missingApplications
                          .containsKey(index);

                      Color primaryColor;
                      final sliderTag = _sliderTags[index];

                      if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
                        primaryColor = AppTheme.deviceSliderColor;
                      } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
                        primaryColor = AppTheme.masterSliderColor;
                      } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
                        primaryColor = AppTheme.activeSliderColor;
                      } else if (sliderTag == ConfigManager.TAG_APP) {
                        if (_assignedApps[index] != null) {
                          primaryColor = AppTheme.appSliderColor;
                        } else if (hasMissingApp) {
                          primaryColor = AppTheme.missingAppColor;
                        } else {
                          primaryColor = AppTheme.unassignedSliderColor;
                        }
                      } else {
                        primaryColor = AppTheme.unassignedSliderColor;
                      }

                      Widget sliderWidget = VerticalSliderCard(
                        title: title,
                        iconWidget: iconWidget,
                        value: _sliderValues[index] / 1024,
                        isMuted: isMuted,
                        isActive: isActive,
                        percentage: volumePercentage,
                        accentColor: hasMissingApp
                            ? AppTheme.missingAppColor
                            : (_sliderColors[index] ?? primaryColor),
                        accentOpacity:
                            hasMissingApp && _pulseAnimations.containsKey(index)
                                ? _pulseAnimations[index]!.value
                                : 1.0,
                        onSliderChanged: (value) {
                          final scaledValue = value * 1024;
                          _handleVolumeAdjustment(index, scaledValue);
                        },
                        onMutePressed: () => _toggleMute(index),
                        onTap: () => _selectApp(index),
                        isDarkMode: isDarkMode,
                      );

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingXSmall),
                          child: sliderWidget,
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
