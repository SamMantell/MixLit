// lib/frontend/home_page.dart

import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/worker.dart';
import 'package:mixlit/backend/application/get_application.dart';
import 'package:win32audio/win32audio.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Worker _worker = Worker();
  final ApplicationManager _applicationManager = ApplicationManager();
  final ScrollController _scrollController = ScrollController();

  List<double> _sliderValues = [0, 0, 0, 0, 0];
  List<ProcessVolume?> _assignedApps = [null, null, null, null, null];
  Map<String, Uint8List?> _appIcons = {};

  @override
  void initState() {
    super.initState();

    // Listen to the slider stream from Worker to update slider values
    _worker.sliderStream.listen((data) {
      setState(() {
        data.forEach((sliderId, sliderValue) {
          if (sliderId >= 0 && sliderId < _sliderValues.length) {
            _sliderValues[sliderId] = sliderValue.toDouble();
            _applicationManager.adjustVolume(sliderId, sliderValue.toDouble()); // Update the application volume
          }
        });
      });
    });
  }

  Future<void> _assignApplication(int sliderIndex) async {
    List<ProcessVolume> runningApps = await _applicationManager.getRunningApplicationsWithAudio();
    await _fetchAllAppIcons(runningApps);

    ProcessVolume? selectedApp = await showDialog<ProcessVolume>(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select Application',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      controller: _scrollController,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: runningApps.length,
                      itemBuilder: (context, index) {
                        final app = runningApps[index];
                        final iconData = _appIcons[app.processPath];
                        final appName = _formatAppName(app.processPath.split(r'\').last);

                        return GestureDetector(
                          onTap: () => Navigator.pop(context, app),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.black.withOpacity(0.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                iconData != null
                                    ? Image.memory(
                                        iconData,
                                        width: 128,
                                        height: 128,
                                      )
                                    : const Icon(Icons.apps, color: Colors.white, size: 128),
                                const SizedBox(height: 8),
                                Text(
                                  appName,
                                  style: const TextStyle(color: Colors.white, fontSize: 24),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedApp != null) {
      setState(() {
        _assignedApps[sliderIndex] = selectedApp;
      });
      _applicationManager.assignApplicationToSlider(sliderIndex, selectedApp);
    }
  }

  Future<void> _fetchAllAppIcons(List<ProcessVolume> apps) async {
    for (var app in apps) {
      if (!_appIcons.containsKey(app.processPath)) {
        _appIcons[app.processPath] = await nativeIconToBytes(app.processPath);
      }
    }
    setState(() {}); // Update the UI to reflect the loaded icons
  }

  String _formatAppName(String appName) {
    appName = appName.replaceAll('.exe', '');
    return appName[0].toUpperCase() + appName.substring(1);
  }

  @override
  void dispose() {
    _worker.dispose();
    _scrollController.dispose(); // Dispose of the scroll controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    // Calculate a base width for the container based on screen size and keep aspect ratio
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
              clipBehavior: Clip.none, // Allow overflow of the logo
              children: [
                // Slider Container
                Container(
                  width: containerWidth,
                  height: containerHeight,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(_sliderValues.length, (index) {
                          final appName = _assignedApps[index] != null
                              ? _formatAppName(_assignedApps[index]!.processPath.split(r'\').last)
                              : 'Unassigned';
                          final volumePercentage = (_sliderValues[index] / 1024 * 100).round();

                          Uint8List? iconData;
                          if (_assignedApps[index] != null) {
                            final appPath = _assignedApps[index]!.processPath;
                            iconData = _appIcons[appPath];
                          }

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: containerHeight * 0.5, // Proportional height for slider
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: _sliderValues[index],
                                    min: 0,
                                    max: 1024,
                                    activeColor: Colors.blueGrey,
                                    inactiveColor: Colors.blueGrey.withOpacity(0.5),
                                    onChanged: (newValue) async {
                                      setState(() {
                                        _sliderValues[index] = newValue;
                                      });
                                      _applicationManager.adjustVolume(index, newValue);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              iconData != null
                                  ? Image.memory(
                                      iconData,
                                      width: 32,
                                      height: 32,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.image_not_supported, color: Colors.white),
                                    )
                                  : const Icon(Icons.apps, color: Colors.white, size: 32),
                              const SizedBox(height: 10),
                              Text(
                                appName,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                "$volumePercentage%",
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                                onPressed: () => _assignApplication(index),
                                tooltip: 'Select application',
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                // Logo above the container with overlap
                Positioned(
                  top: -containerHeight * 0.25, // Adjust for overlap
                  child: Image.asset(
                    'lib/frontend/assets/images/logo/mixlit_full.png',
                    height: containerHeight * 0.2,
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