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

  //removes apps already assigned to a slider
  final availableApps = runningApps.where((app) {
    for (var i = 0; i < assignedApps.length; i++) {
      if (i != sliderIndex && assignedApps[i] != null) {
        final assignedApp = assignedApps[i]!;
        final configManager = ConfigManager.instance;

        if (configManager.normalizeProcessName(
                configManager.extractProcessName(assignedApp.processPath)) ==
            configManager.normalizeProcessName(
                configManager.extractProcessName(app.processPath))) {
          return false; // This app is already assigned, so exclude it
        }
      }
    }
    return true;
  }).toList();

  dynamic result = await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

      return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const NetworkImage(
                    'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAwIiBoZWlnaHQ9IjIwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8ZGVmcz4KICAgIDxmaWx0ZXIgaWQ9Im5vaXNlIj4KICAgICAgPGZlVHVyYnVsZW5jZSBiYXNlRnJlcXVlbmN5PSIwLjkiIG51bU9jdGF2ZXM9IjQiIHNlZWQ9IjIiLz4KICAgICAgPGZlQ29sb3JNYXRyaXggdHlwZT0ic2F0dXJhdGUiIHZhbHVlcz0iMCIvPgogICAgPC9maWx0ZXI+CiAgPC9kZWZzPgogIDxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbHRlcj0idXJsKCNub2lzZSkiIG9wYWNpdHk9IjAuMDUiLz4KPC9zdmc+'),
                repeat: ImageRepeat.repeat,
                opacity: 0.9,
              ),
            ),
            child: Stack(
              children: [
                DefaultTabController(
                  length: 2,
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.6,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF1E1E1E)
                            : const Color.fromARGB(255, 214, 214, 214),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.1),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(
                                child: Text(
                                  'Applications',
                                  style: TextStyle(
                                    fontFamily: 'BitstreamVeraSans',
                                  ),
                                ),
                              ),
                              Tab(
                                child: Text(
                                  'System',
                                  style: TextStyle(
                                    fontFamily: 'BitstreamVeraSans',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Applications Tab
                                ListView.builder(
                                  itemCount: availableApps.length,
                                  itemBuilder: (context, index) {
                                    final app = availableApps[index];
                                    final iconData = appIcons[app.processPath];
                                    final appName = _formatAppName(
                                        app.processPath.split(r'\').last);

                                    return ListTile(
                                      leading: iconData != null
                                          ? Image.memory(
                                              iconData,
                                              width: 32,
                                              height: 32,
                                            )
                                          : const Icon(Icons.apps,
                                              color: Colors.white),
                                      title: Text(
                                        appName,
                                        style: const TextStyle(
                                          fontFamily: 'BitstreamVeraSans',
                                          color: Colors.white,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(context,
                                            {'type': 'app', 'app': app});
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
                                        style: TextStyle(
                                          fontFamily: 'BitstreamVeraSans',
                                          color: Colors.white,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(
                                            context, {'type': 'device'});
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.volume_up,
                                          color: Colors.white),
                                      title: const Text(
                                        'Master Volume',
                                        style: TextStyle(
                                          fontFamily: 'BitstreamVeraSans',
                                          color: Colors.white,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(
                                            context, {'type': 'master'});
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                          Icons.app_registration,
                                          color: Colors.white),
                                      title: const Text(
                                        'Active Application Volume',
                                        style: TextStyle(
                                          fontFamily: 'BitstreamVeraSans',
                                          color: Colors.white,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(
                                            context, {'type': 'active'});
                                      },
                                    ),
                                    const Divider(color: Colors.white30),
                                    ListTile(
                                      leading: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      title: const Text(
                                        'Reset Slider',
                                        style: TextStyle(
                                          fontFamily: 'BitstreamVeraSans',
                                          color: Colors.red,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(
                                            context, {'type': 'reset'});
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
                //app assigner close button
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.5 -
                      (MediaQuery.of(context).size.height * 0.48),
                  right: MediaQuery.of(context).size.width * 0.2 - 12,
                  child: Transform.rotate(
                    angle: 8 * (3.14159 / 180),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F1E5).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFF3F1E5).withOpacity(0.5),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Color(0xFF333333),
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ));
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

Widget _buildSystemOption(
  BuildContext context,
  bool isDarkMode,
  IconData icon,
  String title,
  String subtitle,
  VoidCallback onTap, {
  bool isDestructive = false,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      color: Colors.transparent,
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDestructive
                      ? Colors.red.withOpacity(0.1)
                      : isDarkMode
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1),
                  border: isDestructive
                      ? Border.all(color: Colors.red.withOpacity(0.3))
                      : null,
                ),
                child: Icon(
                  icon,
                  color: isDestructive
                      ? Colors.red
                      : isDarkMode
                          ? Colors.white
                          : Colors.black54,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: isDestructive
                            ? Colors.red
                            : isDarkMode
                                ? Colors.white
                                : const Color.fromARGB(255, 92, 92, 92),
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: isDestructive
                            ? Colors.red.withOpacity(0.7)
                            : isDarkMode
                                ? Colors.white.withOpacity(0.6)
                                : const Color.fromARGB(255, 92, 92, 92)
                                    .withOpacity(0.6),
                        fontSize: 13,
                      ),
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

  if (appName.isEmpty) {
    return 'Unknown';
  }

  return appName[0].toUpperCase() + appName.substring(1);
}
