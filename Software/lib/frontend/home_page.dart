import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/menu/slider_assignment.dart';
import 'package:mixlit/frontend/components/slider_container.dart';
import 'package:mixlit/frontend/menu/dialog/warning.dart';
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

  final List<double> _sliderValues = [0, 0, 0, 0, 0];
  List<ProcessVolume?> _assignedApps = [null, null, null, null, null];
  final Map<String, Uint8List?> _appIcons = {};
  final List<String> _sliderTags = ['unassigned', 'unassigned', 'unassigned', 'unassigned', 'unassigned'];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_worker.deviceConnected) {
        FailedToConnectToDeviceDialog.show(
          context, 
          "Couldn't detect your MixLit, app will maintain basic functionality."
        );
      }
    });

    // Listen to the slider stream from Worker to update slider values
    _worker.sliderStream.listen((data) {
      setState(() {
        data.forEach((sliderId, sliderValue) {
          if (sliderId >= 0 && sliderId < _sliderValues.length) {
            _sliderValues[sliderId] = sliderValue.toDouble();
            // Adjust volume based on whether it's a default device or app
            if (_sliderTags[sliderId] == 'defaultDevice') {
              _applicationManager.adjustDeviceVolume(sliderValue.toDouble());
            } else if (_sliderTags[sliderId] == 'app') {
              _applicationManager.adjustVolume(sliderId, sliderValue.toDouble());
            }
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    // Calculate container size based on screen dimensions
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
                  sliderTags: _sliderTags,  // Pass sliderTags to SliderContainer
                  onAssignApp: (sliderIndex) async {
                    _assignedApps = await assignApplication(
                      context,
                      sliderIndex,
                      _applicationManager,
                      _assignedApps,
                      _appIcons,
                      _sliderValues,
                      _sliderTags, // Pass sliderTags
                    );
                    setState(() {});
                  },
                  onSliderChange: (sliderIndex, value) {
                    setState(() {
                      _sliderValues[sliderIndex] = value;
                  
                      // Check if it's assigned to an app or the default device
                      if (_sliderTags[sliderIndex] == 'defaultDevice') {
                        _applicationManager.adjustDeviceVolume(value);
                      } else if (_sliderTags[sliderIndex] == 'app' && _assignedApps[sliderIndex] != null) {
                        // Ensure that an app is assigned to this slider before adjusting the volume
                        _applicationManager.adjustVolume(sliderIndex, value);
                      } else {
                        print("No application assigned to this slider.");
                      }
                    });
                  },
                  onSelectDefaultDevice: (sliderIndex, isDefault) {
                    setState(() {
                      _sliderTags[sliderIndex] = isDefault ? 'defaultDevice' : 'unassigned';
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