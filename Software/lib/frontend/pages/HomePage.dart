import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/audio/MuteState.dart';
import 'package:mixlit/backend/application/audio/VolumeController.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/backend/application/integration/SonosIntegration.dart';
import 'package:mixlit/backend/application/integration/SpotifyIntegration.dart';
import 'package:mixlit/backend/serial/DeviceServiceClient.dart';
import 'package:mixlit/backend/Updater.dart';
import 'package:mixlit/frontend/Theme.dart';
import 'package:mixlit/frontend/components/HorizontalDialCard.dart';
import 'package:mixlit/frontend/components/VerticalSliderCard.dart';
import 'package:mixlit/frontend/components/util/rate_limit_updates.dart';
import 'package:mixlit/frontend/controllers/ConnectionHandler.dart';
import 'package:mixlit/frontend/controllers/DeviceEventHandler.dart';
import 'package:mixlit/frontend/helpers/SliderColorHelper.dart';
import 'package:mixlit/frontend/helpers/SliderDisplayHelper.dart';
import 'package:mixlit/frontend/menus/AssignApplicationMenu.dart';
import 'package:mixlit/frontend/menus/SettingsMenu.dart';
import 'package:mixlit/frontend/menus/dialog/Update.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class HomePage extends StatefulWidget {
  final bool isAutoStarted;
  final Function(bool)? onThemeChanged;

  const HomePage({
    super.key,
    this.isAutoStarted = false,
    this.onThemeChanged,
    required Future<void> Function() onSettingsChanged,
  });

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WindowListener, TrayListener {
  final DeviceServiceClient _worker = DeviceServiceClient();
  final AudioServiceClient _audioServiceClient = AudioServiceClient();
  late final ApplicationManager _applicationManager;

  late final MuteButtonController _muteButtonController;
  final ConnectionHandler _connectionHandler = ConnectionHandler();
  VolumeController? _volumeController;
  DeviceEventHandler? _deviceEventHandler;

  late SliderDisplayHelper _display;
  late SliderColorHelper _colorHelper;

  final List<double> _sliderValues = List.filled(8, 0.0);
  Map<int, int>? _pendingHardwareValues;
  List<AudioSessionInfo?> _assignedApps = List.filled(8, null);
  List<String> _sliderTags = List.filled(8, 'unassigned');
  final Map<String, Uint8List?> _appIcons = {};
  final Map<String, Uint8List?> _cachedAppIcons = {};
  final Map<int, Color> _sliderColors = {};
  bool _configLoaded = false;
  bool _audioServiceConnected = false;
  UpdateInfo? _pendingUpdate;

  late final RateLimitedUpdater _uiUpdater;

  final Map<int, AnimationController> _pulseControllers = {};
  final Map<int, Animation<double>> _pulseAnimations = {};

  StreamSubscription? _initialHardwareValuesSubscription;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initTray();

    _uiUpdater =
        RateLimitedUpdater(const Duration(milliseconds: 2), _performUIUpdate);

    _muteButtonController = MuteButtonController(
      buttonCount: 8,
      vsync: this,
      onVolumeAdjustment: _handleDirectVolumeAdjustment,
      onSliderValueUpdated: _updateSliderValue,
    );

    _initializeServices();
  }

  @override
  void dispose() {
    for (final c in _pulseControllers.values) c.dispose();
    _pulseControllers.clear();
    _pulseAnimations.clear();

    _uiUpdater.dispose();
    _initialHardwareValuesSubscription?.cancel();
    _worker.dispose();
    _muteButtonController.dispose();

    if (_configLoaded) {
      _deviceEventHandler?.dispose();
      _volumeController?.dispose();
      _connectionHandler.dispose();
      _applicationManager.dispose();
    }

    _audioServiceClient.dispose();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  void _showPendingUpdate() {
    if (_pendingUpdate != null && mounted) {
      // Don't clear _pendingUpdate here — keep it so the badge and
      // settings banner remain visible until they actually accept.
      Updater().showUpdateDialog(context, _pendingUpdate!).then((accepted) {
        if (accepted == true && mounted) {
          setState(() => _pendingUpdate = null);
        }
      });
    }
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> _initializeServices() async {
    try {
      print('⌚ Connecting to device service...');
      await _worker.connect();

      _initialHardwareValuesSubscription =
          _worker.initialHardwareValues.listen((values) {
        _pendingHardwareValues = values;
        if (_volumeController != null) _restoreHardwareValues(values);
      });

      print('⌚ Connecting to audio service...');
      await _audioServiceClient.connect();
      _audioServiceConnected = true;

      print('⌚ Creating ApplicationManager...');
      _applicationManager = ApplicationManager(_audioServiceClient);
      await _applicationManager.configLoaded;

      print('⌚ Initialising integrations...');
      await SpotifyIntegration.instance.initialize();

      print('⌚ Loading configuration...');
      await _loadConfiguration();

      print('⌚ Loading noise reduction threshold...');
      _worker.noiseThreshold = await SettingsManager.getNoiseReduction();

      print('⌚ Setting up helpers...');
      _colorHelper = SliderColorHelper(
        audioServiceClient: _audioServiceClient,
        audioServiceConnected: _audioServiceConnected,
      );
      _display = SliderDisplayHelper(
        applicationManager: _applicationManager,
        assignedApps: _assignedApps,
        sliderTags: _sliderTags,
        appIcons: _appIcons,
        cachedAppIcons: _cachedAppIcons,
      );

      await _refreshAllColors();

      print('⌚ Setting up volume controller...');
      _volumeController = VolumeController(
        applicationManager: _applicationManager,
        sliderTags: _sliderTags,
        assignedApps: _assignedApps,
      );
      _muteButtonController.setVolumeController(_volumeController!);
      for (int i = 0; i < _muteButtonController.muteStates.length; i++) {
        _volumeController!
            .updateMuteState(i, _muteButtonController.muteStates[i]);
      }

      print('⌚ Setting up device event handler...');
      _deviceEventHandler = DeviceEventHandler(
        worker: _worker,
        onSliderDataReceived: _handleSliderData,
        onButtonEvent: _handleButtonEvent,
        onConnectionStateChanged: _handleConnectionStateChanged,
      );
      _deviceEventHandler!.initialize();

      _connectionHandler.initializeDeviceConnection(
          context, _worker.isDeviceConnected);

      if (_pendingHardwareValues != null) {
        _restoreHardwareValues(_pendingHardwareValues!);
      } else if (_worker.isDeviceConnected) {
        final values = await _worker.requestInitialHardwareValues();
        if (values != null) _restoreHardwareValues(values);
      }

      setState(() => _configLoaded = true);

      _checkForUpdates();
      _startPeriodicUIUpdates();

      print('✅ Setup complete - YIPPEEEE ✅');
    } catch (e) {
      print('Error initializing services: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to connect to audio service: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      _sliderTags =
          List.from(_applicationManager.sliderTags.take(_sliderTags.length));

      for (int i = 0;
          i < _muteButtonController.muteStates.length &&
              i < _applicationManager.muteStates.length;
          i++) {
        _muteButtonController.muteStates[i] = _applicationManager.muteStates[i];
      }

      for (int i = 0; i < _sliderTags.length; i++) {
        _assignedApps[i] = _sliderTags[i] == ConfigManager.TAG_APP
            ? _applicationManager.assignedApplications[i]
            : null;
      }
    });
  }

  void _restoreHardwareValues(Map<int, int> hardwareValues) {
    if (_volumeController == null) return;

    _worker.seedNoiseBaseline(hardwareValues);

    hardwareValues.forEach((sliderId, rawValue) {
      if (sliderId < 0 || sliderId >= _sliderValues.length) return;
      final value = rawValue.toDouble();
      _sliderValues[sliderId] = value;
      _muteButtonController.updatePreviousVolumeValue(sliderId, value);
      if (_muteButtonController.muteStates[sliderId]) {
        _volumeController!.storeVolumeValue(sliderId, value);
      } else {
        _volumeController!.adjustVolume(sliderId, value,
            bypassRateLimit: true, fromRestore: true);
      }
    });

    if (mounted) setState(() {});
  }

  void _startPeriodicUIUpdates() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && _configLoaded) _syncSliderStates();
    });
  }

  void _syncSliderStates() {
    bool needsUpdate = false;

    for (int i = 0; i < _sliderTags.length; i++) {
      if (_sliderTags[i] != ConfigManager.TAG_APP) continue;

      final current = _assignedApps[i];
      final manager = _applicationManager.assignedApplications[i];
      final hasMissing = _applicationManager.missingApplications.containsKey(i);

      if ((current == null) != (manager == null)) {
        _assignedApps[i] = manager;
        _display.updateAssignedApps(_assignedApps);
        needsUpdate = true;
        if (manager != null) {
          _disposeAnimation(i);
          _colorHelper.loadIcon(manager.processPath, _appIcons);
        }
      }

      if (hasMissing && !_pulseControllers.containsKey(i)) {
        _createAnimation(i);
        needsUpdate = true;
      } else if (!hasMissing && _pulseControllers.containsKey(i)) {
        _disposeAnimation(i);
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      _refreshAllColors().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _createAnimation(int index) {
    if (_pulseControllers.containsKey(index)) return;
    final controller =
        AnimationController(duration: const Duration(seconds: 2), vsync: this);
    final animation = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    _pulseControllers[index] = controller;
    _pulseAnimations[index] = animation;
    animation.addListener(() {
      if (mounted) setState(() {});
    });
    controller.repeat(reverse: true);
  }

  void _disposeAnimation(int index) {
    _pulseControllers[index]?.dispose();
    _pulseControllers.remove(index);
    _pulseAnimations.remove(index);
  }

  Future<void> _refreshAllColors() async {
    final colors = await _colorHelper.resolveAllColors(
      applicationManager: _applicationManager,
      assignedApps: _assignedApps,
      sliderTags: _sliderTags,
      appIcons: _appIcons,
      cachedAppIcons: _cachedAppIcons,
    );
    if (mounted)
      setState(() {
        _sliderColors
          ..clear()
          ..addAll(colors);
      });
  }

  Future<void> _refreshColor(int index) async {
    final color = await _colorHelper.resolveColor(
      index: index,
      applicationManager: _applicationManager,
      assignedApps: _assignedApps,
      sliderTags: _sliderTags,
      appIcons: _appIcons,
      cachedAppIcons: _cachedAppIcons,
    );
    if (mounted) setState(() => _sliderColors[index] = color);
  }

  void _handleSliderData(Map<int, int> data) {
    if (!_configLoaded) return;
    // (noise gate filtered) data entry
    data.forEach((id, raw) {
      if (id < 0 || id >= _sliderValues.length) return;
      final value = raw.toDouble();
      _sliderValues[id] = value;
      _muteButtonController.updatePreviousVolumeValue(id, value);
      if (_muteButtonController.muteStates[id]) {
        _volumeController!.storeVolumeValue(id, value);
      } else {
        _volumeController!.adjustVolume(id, value);
      }
    });
    _uiUpdater.requestUpdate();
  }

  void _handleButtonEvent(int index, bool isPressed, bool isReleased) {
    if (!_configLoaded) return;
    if (isPressed) {
      _muteButtonController.handleButtonDown(index);
      _muteButtonController.checkLongPress(index);
    } else if (isReleased) {
      _muteButtonController.handleButtonUp(index);
    }
    _uiUpdater.requestUpdate();
  }

  void _handleConnectionStateChanged(bool connected) {
    if (!mounted) return;
    _connectionHandler.showConnectionNotification(context, connected);
    if (connected && _configLoaded) {
      _loadConfiguration();
    }
  }

  void _handleVolumeAdjustment(int id, double value) {
    _sliderValues[id] = value;
    _muteButtonController.updatePreviousVolumeValue(id, value);
    if (_muteButtonController.muteStates[id]) {
      _volumeController!.storeVolumeValue(id, value);
    } else {
      _volumeController!.adjustVolume(id, value,
          bypassRateLimit: value <= MuteButtonController.muteVolume);
    }
    _uiUpdater.requestUpdate();
  }

  void _handleDirectVolumeAdjustment(int id, double value) {
    _sliderValues[id] = value;
    _volumeController!.directVolumeAdjustment(id, value);
    _uiUpdater.requestUpdate();
  }

  void _updateSliderValue(int id, double value) {
    _sliderValues[id] = value;
    _uiUpdater.requestUpdate();
  }

  void _toggleMute(int index) {
    if (!_muteButtonController.muteStates[index]) {
      _muteButtonController.previousVolumeValues[index] = _sliderValues[index];
      _volumeController!.storeVolumeValue(index, _sliderValues[index]);
    }
    _muteButtonController.toggleMuteState(index);
    _uiUpdater.requestUpdate();
  }

  void _performUIUpdate() {
    if (mounted && _configLoaded) setState(() {});
  }

  Future<void> _selectApp(int index) async {
    try {
      final prevApp = _assignedApps[index];
      final prevTag = _sliderTags[index];

      final result = await assignApplication(
        context,
        index,
        _applicationManager,
        _assignedApps,
        _appIcons,
        _sliderValues,
        _sliderTags,
      );

      if (result is Map<String, dynamic> && result['isIntegration'] == true) {
        await _applicationManager.assignIntegrationToSlider(
            index, result['integrationData']);
        setState(() {
          _sliderTags[index] = ConfigManager.TAG_INTEGRATION;
          _assignedApps[index] = null;
          _volumeController!.updateSliderTags(_sliderTags);
          _volumeController!.updateAssignedApps(_assignedApps);
        });
        await _refreshColor(index);
        return;
      }

      if (result is List<AudioSessionInfo?>) {
        _assignedApps = result;
        _display.updateAssignedApps(_assignedApps);

        if (prevApp != _assignedApps[index] || prevTag != _sliderTags[index]) {
          await _refreshColor(index);
        }

        setState(() {
          _volumeController!.updateSliderTags(_sliderTags);
          _volumeController!.updateAssignedApps(_assignedApps);
        });
      }
    } catch (e, stack) {
      print('_selectApp($index) error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open app selector: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon('lib/frontend/assets/images/logo/app_icon.ico');
    await trayManager.setToolTip("MixLit: Application Volume Control");
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(label: "Show Window", onClick: (_) => _showWindow()),
      MenuItem(label: "Close", onClick: (_) => _exitApp()),
    ]));
  }

  void _showWindow() {
    windowManager.show();
    windowManager.focus();
    _showPendingUpdate();
  }

  void _exitApp() {
    trayManager.destroy();
    windowManager.destroy();
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onWindowClose() async {
    if (await SettingsManager.getMinimizeToTray()) {
      windowManager.hide();
    } else {
      _exitApp();
    }
  }

  // ── Misc ───────────────────────────────────────────────────────────────────

  Future<void> _checkForUpdates() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateInfo = await Updater().checkForUpdates();
    if (updateInfo == null) return;

    setState(() => _pendingUpdate = updateInfo);

    final isVisible = await windowManager.isVisible();
    if (mounted && isVisible) {
      Updater().showUpdateDialog(context, updateInfo).then((accepted) {
        if (accepted == true && mounted) {
          setState(() => _pendingUpdate = null);
        }
      });
    }
  }

  void _onSettingsPressed() async {
    await showSettingsDialog(
      context,
      rawDataStream: _worker.rawData,
      sliderDataStream: _worker.sliderData,
      buttonDataStream: _worker.buttonData,
      onThemeChanged: widget.onThemeChanged,
      pendingUpdate: _pendingUpdate,
    );
    _worker.noiseThreshold = await SettingsManager.getNoiseReduction();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_configLoaded) {
      return DragToMoveArea(
        child: Scaffold(
          backgroundColor: AppTheme.getBackgroundColor(isDark),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                SizedBox(height: AppTheme.spacingLarge),
                Text('Starting Services...',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.getPrimaryTextColor(isDark))),
              ],
            ),
          ),
        ),
      );
    }

    return DragToMoveArea(
      child: Scaffold(
        backgroundColor: AppTheme.getSecondaryBackgroundColor(isDark),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isDark),
                SizedBox(height: AppTheme.spacingLarge),
                _buildDialRow(isDark),
                SizedBox(height: AppTheme.spacingMedium),
                Expanded(child: _buildSliderRow(isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Stack(children: [
      Row(children: [
        const SizedBox(width: 150),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('lib/frontend/assets/images/logo/mixlit_full.png',
                  height: AppTheme.iconSizeXLarge, fit: BoxFit.contain),
              SizedBox(height: AppTheme.spacingSmall),
              Text('Volume Mixer Thingy Majig 9000',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: AppTheme.getPrimaryTextColor(isDark))),
            ],
          ),
        ),
        SizedBox(
          width: 150,
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _headerButton(Icons.settings, _onSettingsPressed, isDark,
                  showBadge: _pendingUpdate != null),
              SizedBox(
                  width: AppTheme.spacingSmall), // ← was accidentally removed
              _headerButton(Icons.close, () => windowManager.hide(), isDark,
                  destructive: true),
            ]),
          ),
        ),
      ]),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ListenableBuilder(
            listenable: _connectionHandler,
            builder: (context, _) {
              final connected = _connectionHandler.isCurrentlyConnected;
              return Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMedium,
                    vertical: AppTheme.spacingSmall),
                decoration:
                    AppTheme.getStatusIndicatorDecoration(connected, isDark),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    connected ? Icons.usb_rounded : Icons.usb_off_rounded,
                    color: AppTheme.getConnectionColor(connected),
                    size: AppTheme.iconSizeSmall,
                  ),
                  SizedBox(width: AppTheme.spacingXSmall),
                  Text(connected ? 'Connected' : 'Disconnected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.getConnectionColor(connected))),
                ]),
              );
            },
          ),
        ),
      ),
    ]);
  }

  Widget _headerButton(IconData icon, VoidCallback onTap, bool isDark,
      {bool destructive = false, bool showBadge = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
        child: Container(
          padding: EdgeInsets.all(AppTheme.spacingSmall),
          decoration:
              AppTheme.getButtonDecoration(isDark, isDestructive: destructive),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon,
                  color: destructive
                      ? AppTheme.errorColor
                          .withOpacity(AppTheme.opacityAlmostOpaque)
                      : AppTheme.getPrimaryTextColor(isDark)
                          .withOpacity(AppTheme.opacityAlmostOpaque),
                  size: AppTheme.iconSizeMedium),
              if (showBadge)
                Positioned(
                  left: -2,
                  bottom: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.getSecondaryBackgroundColor(isDark),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialRow(bool isDark) {
    return SizedBox(
      height: AppTheme.dialCardHeight,
      child: Row(
        children: List.generate(3, (i) {
          final dialIndex = i + 5;
          final hasMissing =
              _applicationManager.missingApplications.containsKey(dialIndex);
          final fallback = _display.staticColor(dialIndex);

          return Expanded(
            child: HorizontalDialCard(
              title: _display.buildDialTitle(dialIndex),
              iconWidget: _display.buildDialIcon(dialIndex),
              value: _sliderValues[dialIndex] / 1024,
              isActive: _display.isSliderActive(dialIndex),
              percentage: (_sliderValues[dialIndex] / 1024 * 100).round(),
              accentColor: hasMissing
                  ? AppTheme.missingAppColor
                  : (_sliderColors[dialIndex] ?? fallback),
              accentOpacity:
                  hasMissing && _pulseAnimations.containsKey(dialIndex)
                      ? _pulseAnimations[dialIndex]!.value
                      : 1.0,
              onDialChanged: (v) =>
                  _handleVolumeAdjustment(dialIndex, v * 1024),
              onTap: () => _selectApp(dialIndex),
              isDarkMode: isDark,
              hasIntegration: _applicationManager.assignedIntegrations
                  .containsKey(dialIndex),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSliderRow(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(5, (index) {
        final hasMissing =
            _applicationManager.missingApplications.containsKey(index);
        final fallback = _display.staticColor(index);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingXSmall),
            child: VerticalSliderCard(
              title: _display.buildSliderTitle(index),
              iconWidget: _display.buildSliderIcon(index),
              value: _sliderValues[index] / 1024,
              isMuted: _muteButtonController.muteStates[index],
              isActive: _display.isSliderActive(index),
              percentage: (_sliderValues[index] / 1024 * 100).round(),
              accentColor: hasMissing
                  ? AppTheme.missingAppColor
                  : (_sliderColors[index] ?? fallback),
              accentOpacity: hasMissing && _pulseAnimations.containsKey(index)
                  ? _pulseAnimations[index]!.value
                  : 1.0,
              onSliderChanged: (v) => _handleVolumeAdjustment(index, v * 1024),
              onMutePressed: () => _toggleMute(index),
              onTap: () => _selectApp(index),
              isDarkMode: isDark,
              hasIntegration:
                  _applicationManager.assignedIntegrations.containsKey(index),
            ),
          ),
        );
      }),
    );
  }
}
