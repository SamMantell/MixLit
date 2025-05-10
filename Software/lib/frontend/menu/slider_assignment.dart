import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:mixlit/backend/application/AppInstanceManager.dart';

Future<List<ProcessVolume?>> assignApplication(
  BuildContext context,
  int sliderIndex,
  ApplicationManager applicationManager,
  List<ProcessVolume?> assignedApps,
  Map<String, Uint8List?> appIcons,
  List<double> sliderValues,
  List<String> sliderTags,
) async {
  final appInstanceManager = AppInstanceManager.instance;
  final runningApps = await appInstanceManager.getUniqueApps();
  await fetchAllAppIcons(runningApps, appIcons);

  final previousTag = sliderTags[sliderIndex];
  final previousApp = assignedApps[sliderIndex];

  dynamic result = await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DefaultTabController(
          length: 2,
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
                  const TabBar(
                    tabs: [
                      Tab(text: 'Applications'),
                      Tab(text: 'System'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Applications Tab
                        ListView.builder(
                          itemCount: runningApps.length,
                          itemBuilder: (context, index) {
                            final app = runningApps[index];
                            final iconData = appIcons[app.processPath];
                            final appName = _formatAppName(
                                app.processPath.split(r'\').last);
                            //TODO: make apps deregister from assignment list if alr assigned
                            bool isAlreadyAssigned = false;
                            int? assignedSliderIndex;

                            for (var i = 0; i < assignedApps.length; i++) {
                              if (i != sliderIndex && assignedApps[i] != null) {
                                final assignedApp = assignedApps[i]!;
                                final configManager = ConfigManager.instance;

                                if (configManager.normalizeProcessName(
                                        configManager.extractProcessName(
                                            assignedApp.processPath)) ==
                                    configManager.normalizeProcessName(
                                        configManager.extractProcessName(
                                            app.processPath))) {
                                  isAlreadyAssigned = true;
                                  assignedSliderIndex = i;
                                  break;
                                }
                              }
                            }

                            return ListTile(
                              leading: iconData != null
                                  ? Image.memory(
                                      iconData,
                                      width: 32,
                                      height: 32,
                                    )
                                  : const Icon(Icons.apps, color: Colors.white),
                              title: Text(
                                appName,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: isAlreadyAssigned
                                  ? Text(
                                      'Already assigned to Slider ${assignedSliderIndex! + 1}',
                                      style:
                                          TextStyle(color: Colors.orange[200]),
                                    )
                                  : null,
                              onTap: () {
                                Navigator.pop(
                                    context, {'type': 'app', 'app': app});
                              },
                            );
                          },
                        ),
                        ListView(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.speaker,
                                  color: Colors.white),
                              title: const Text(
                                'Device Volume',
                                style: TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                Navigator.pop(context, {'type': 'device'});
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.volume_up,
                                  color: Colors.white),
                              title: const Text(
                                'Master Volume',
                                style: TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                Navigator.pop(context, {'type': 'master'});
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.app_registration,
                                  color: Colors.white),
                              title: const Text(
                                'Active Application Volume',
                                style: TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                Navigator.pop(context, {'type': 'active'});
                              },
                            ),
                            const Divider(color: Colors.white30),
                            ListTile(
                              leading: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              title: const Text(
                                'Reset Slider',
                                style: TextStyle(color: Colors.red),
                              ),
                              onTap: () {
                                Navigator.pop(context, {'type': 'reset'});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  // Handle the dialog result
  if (result != null && result is Map<String, dynamic>) {
    final type = result['type'];

    switch (type) {
      case 'app':
        final app = result['app'] as ProcessVolume;
        assignedApps[sliderIndex] = app;
        sliderTags[sliderIndex] = ConfigManager.TAG_APP;
        applicationManager.assignApplicationToSlider(sliderIndex, app);

        bool hasMultipleInstances =
            await appInstanceManager.hasMultipleInstances(app);
        if (hasMultipleInstances) {
          double volumeLevel = sliderValues[sliderIndex] / 1024;
          await appInstanceManager.setVolumeForAllInstances(app, volumeLevel);
        }
        break;

      case 'device':
        assignedApps[sliderIndex] = null;
        sliderTags[sliderIndex] = ConfigManager.TAG_DEFAULT_DEVICE;
        applicationManager.assignSpecialFeatureToSlider(
            sliderIndex, ConfigManager.TAG_DEFAULT_DEVICE);
        break;

      case 'master':
        assignedApps[sliderIndex] = null;
        sliderTags[sliderIndex] = ConfigManager.TAG_MASTER_VOLUME;
        applicationManager.assignSpecialFeatureToSlider(
            sliderIndex, ConfigManager.TAG_MASTER_VOLUME);
        break;

      case 'active':
        assignedApps[sliderIndex] = null;
        sliderTags[sliderIndex] = ConfigManager.TAG_ACTIVE_APP;
        applicationManager.assignSpecialFeatureToSlider(
            sliderIndex, ConfigManager.TAG_ACTIVE_APP);
        break;

      case 'reset':
        assignedApps[sliderIndex] = null;
        sliderTags[sliderIndex] = ConfigManager.TAG_UNASSIGNED;
        applicationManager.resetSliderConfiguration(sliderIndex);

        appIcons.remove(sliderIndex);
        break;

      default:
        sliderTags[sliderIndex] = previousTag;
        assignedApps[sliderIndex] = previousApp;
    }
  } else {
    sliderTags[sliderIndex] = previousTag;
    assignedApps[sliderIndex] = previousApp;
  }

  return assignedApps;
}

Future<void> fetchAllAppIcons(
    List<ProcessVolume> apps, Map<String, Uint8List?> appIcons) async {
  for (var app in apps) {
    if (!appIcons.containsKey(app.processPath)) {
      appIcons[app.processPath] = await nativeIconToBytes(app.processPath);
    }
  }
}

String _formatAppName(String appName) {
  appName = appName.replaceAll('.exe', '');
  return appName[0].toUpperCase() + appName.substring(1);
}
