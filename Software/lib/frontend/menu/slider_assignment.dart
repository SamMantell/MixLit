import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/backend/application/get_application.dart';

Future<List<ProcessVolume?>> assignApplication(
  BuildContext context,
  int sliderIndex,
  ApplicationManager applicationManager,
  List<ProcessVolume?> assignedApps,
  Map<String, Uint8List?> appIcons,
  List<double> sliderValues,
  List<String> sliderTags,
) async {
  List<ProcessVolume> runningApps = await applicationManager.getRunningApplicationsWithAudio();
  await fetchAllAppIcons(runningApps, appIcons);

  // Store the previous state before showing dialog
  final previousTag = sliderTags[sliderIndex];
  final previousApp = assignedApps[sliderIndex];

  ProcessVolume? selectedApp = await showDialog<ProcessVolume>(
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
                          final appName = _formatAppName(app.processPath.split(r'\').last);

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
                            onTap: () {
                              print("Selected app: ${app.processPath}");
                              sliderTags[sliderIndex] = 'app';
                              assignedApps[sliderIndex] = app;
                              applicationManager.assignApplicationToSlider(sliderIndex, app);
                              applicationManager.adjustVolume(sliderIndex, sliderValues[sliderIndex]);
                              Navigator.pop(context, app);
                            },
                          );
                        },
                      ),
                      // System Tab
                      ListView(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.speaker, color: Colors.white),
                            title: const Text(
                              'Device Volume',
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () {
                              sliderTags[sliderIndex] = 'defaultDevice'; // Tag this slider as the default device
                              Navigator.pop(context, null);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.apps, color: Colors.white),
                            title: const Text(
                              'Active Application Volume',
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () {
                              // Assign active app tag
                              sliderTags[sliderIndex] = 'app'; // Tag this slider as app
                              Navigator.pop(context, sliderIndex);
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



  if (selectedApp != null) {
    assignedApps[sliderIndex] = selectedApp;
    sliderTags[sliderIndex] = 'app';
    applicationManager.assignApplicationToSlider(sliderIndex, selectedApp);
  } else if (sliderTags[sliderIndex] == 'defaultDevice') {
    assignedApps[sliderIndex] = null;
  } else {
    sliderTags[sliderIndex] = previousTag;
    assignedApps[sliderIndex] = previousApp;
  }

  return assignedApps;
}



Future<void> fetchAllAppIcons(List<ProcessVolume> apps, Map<String, Uint8List?> appIcons) async {
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
