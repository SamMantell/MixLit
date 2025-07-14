import 'dart:typed_data';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/audio/AppInstanceManager.dart';

// New class to represent an app group
class AppGroup {
  final String id;
  final String name;
  final List<String> processNames;
  final Color color;
  final DateTime createdAt;

  AppGroup({
    required this.id,
    required this.name,
    required this.processNames,
    required this.color,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'processNames': processNames,
      'color': color.value,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AppGroup.fromJson(Map<String, dynamic> json) {
    return AppGroup(
      id: json['id'],
      name: json['name'],
      processNames: List<String>.from(json['processNames']),
      color: Color(json['color']),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

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
          return false;
        }
      }
    }
    return true;
  }).toList();

  // Create the noise texture bytes from base64
  const String noiseTextureBase64 =
      'PHN2ZyB3aWR0aD0iMjAwIiBoZWlnaHQ9IjIwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8ZGVmcz4KICAgIDxmaWx0ZXIgaWQ9Im5vaXNlIj4KICAgICAgPGZlVHVyYnVsZW5jZSBiYXNlRnJlcXVlbmN5PSIwLjkiIG51bU9jdGF2ZXM9IjQiIHNlZWQ9IjIiLz4KICAgICAgPGZlQ29sb3JNYXRyaXggdHlwZT0ic2F0dXJhdGUiIHZhbHVlcz0iMCIvPgogICAgPC9maWx0ZXI+CiAgPC9kZWZzPgogIDxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbHRlcj0idXJsKCNub2lzZSkiIG9wYWNpdHk9IjAuMDUiLz4KPC9zdmc+';
  final Uint8List noiseTextureBytes = base64Decode(noiseTextureBase64);

  dynamic result = await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Stack(
          children: [
            DefaultTabController(
              length: 3, // Changed from 2 to 3 to include Groups tab
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.6,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: MemoryImage(noiseTextureBytes),
                      repeat: ImageRepeat.repeat,
                      opacity: 0.05,
                    ),
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
                              'Groups',
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
                                    Navigator.pop(
                                        context, {'type': 'app', 'app': app});
                                  },
                                );
                              },
                            ),
                            // Groups Tab
                            GroupsTabContent(
                              availableApps: availableApps,
                              appIcons: appIcons,
                              isDarkMode: isDarkMode,
                            ),
                            // System Tab
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
                                    Navigator.pop(context, {'type': 'device'});
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
                                    Navigator.pop(context, {'type': 'master'});
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.app_registration,
                                      color: Colors.white),
                                  title: const Text(
                                    'Active Application Volume',
                                    style: TextStyle(
                                      fontFamily: 'BitstreamVeraSans',
                                      color: Colors.white,
                                    ),
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
                                    style: TextStyle(
                                      fontFamily: 'BitstreamVeraSans',
                                      color: Colors.red,
                                    ),
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
      );
    },
  );

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

      case 'group':
        final group = result['group'] as AppGroup;
        assignedApps[sliderIndex] = null; // Groups don't have a single ProcessVolume
        sliderTags[sliderIndex] = ConfigManager.TAG_GROUP;
        applicationManager.assignGroupToSlider(sliderIndex, group);
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

// New widget for the Groups tab content
class GroupsTabContent extends StatefulWidget {
  final List<ProcessVolume> availableApps;
  final Map<String, Uint8List?> appIcons;
  final bool isDarkMode;

  const GroupsTabContent({
    super.key,
    required this.availableApps,
    required this.appIcons,
    required this.isDarkMode,
  });

  @override
  State<GroupsTabContent> createState() => _GroupsTabContentState();
}

class _GroupsTabContentState extends State<GroupsTabContent> {
  List<AppGroup> savedGroups = [];
  bool isCreatingGroup = false;

  @override
  void initState() {
    super.initState();
    _loadSavedGroups();
  }

  Future<void> _loadSavedGroups() async {
    try {
      final configManager = ConfigManager.instance;
      final groups = await configManager.loadAppGroups();
      setState(() {
        savedGroups = groups;
      });
    } catch (e) {
      print('Error loading saved groups: $e');
      setState(() {
        savedGroups = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isCreatingGroup) {
      return GroupCreationWidget(
        availableApps: widget.availableApps,
        appIcons: widget.appIcons,
        isDarkMode: widget.isDarkMode,
        onGroupCreated: (group) {
          setState(() {
            savedGroups.add(group);
            isCreatingGroup = false;
          });
        },
        onCancel: () {
          setState(() {
            isCreatingGroup = false;
          });
        },
      );
    }

    return Column(
      children: [
        // Create new group button
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  isCreatingGroup = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: Colors.white.withOpacity(0.8),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Create New Group',
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Saved groups list
        Expanded(
          child: savedGroups.isEmpty
              ? Center(
                  child: Text(
                    'No groups created yet',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: savedGroups.length,
                  itemBuilder: (context, index) {
                    final group = savedGroups[index];
                    return ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: group.color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.folder,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        group.name,
                        style: const TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        '${group.processNames.length} apps',
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context, {'type': 'group', 'group': group});
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// New widget for creating groups
class GroupCreationWidget extends StatefulWidget {
  final List<ProcessVolume> availableApps;
  final Map<String, Uint8List?> appIcons;
  final bool isDarkMode;
  final Function(AppGroup) onGroupCreated;
  final VoidCallback onCancel;

  const GroupCreationWidget({
    super.key,
    required this.availableApps,
    required this.appIcons,
    required this.isDarkMode,
    required this.onGroupCreated,
    required this.onCancel,
  });

  @override
  State<GroupCreationWidget> createState() => _GroupCreationWidgetState();
}

class _GroupCreationWidgetState extends State<GroupCreationWidget> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedApps = {};
  Color _selectedColor = Colors.blue;

  final List<Color> _availableColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.amber,
    Colors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: widget.onCancel,
            ),
            const Text(
              'Create New Group',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Group name input
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: TextField(
            controller: _nameController,
            style: const TextStyle(
              fontFamily: 'BitstreamVeraSans',
              color: Colors.white,
            ),
            decoration: const InputDecoration(
              hintText: 'Group name',
              hintStyle: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                color: Colors.white54,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Color picker
        const Text(
          'Group Color:',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _availableColors.map((color) {
            final isSelected = _selectedColor == color;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Apps selection
        const Text(
          'Select Applications:',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        // Apps list
        Expanded(
          child: ListView.builder(
            itemCount: widget.availableApps.length,
            itemBuilder: (context, index) {
              final app = widget.availableApps[index];
              final processName = app.processPath.split(r'\').last;
              final appName = _formatAppName(processName);
              final iconData = widget.appIcons[app.processPath];
              final isSelected = _selectedApps.contains(processName);

              return CheckboxListTile(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedApps.add(processName);
                    } else {
                      _selectedApps.remove(processName);
                    }
                  });
                },
                title: Text(
                  appName,
                  style: const TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    color: Colors.white,
                  ),
                ),
                secondary: iconData != null
                    ? Image.memory(
                        iconData,
                        width: 32,
                        height: 32,
                      )
                    : const Icon(Icons.apps, color: Colors.white),
                activeColor: _selectedColor,
                checkColor: Colors.white,
              );
            },
          ),
        ),

        // Create button
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          child: ElevatedButton(
            onPressed: _canCreateGroup() ? _createGroup : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Create Group',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _canCreateGroup() {
    return _nameController.text.trim().isNotEmpty && _selectedApps.isNotEmpty;
  }

  void _createGroup() async {
    final group = AppGroup(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      processNames: _selectedApps.toList(),
      color: _selectedColor,
      createdAt: DateTime.now(),
    );

    // Save the group to storage
    try {
      final configManager = ConfigManager.instance;
      await configManager.saveAppGroup(group);
      widget.onGroupCreated(group);
    } catch (e) {
      print('Error saving group: $e');
      // Still call onGroupCreated even if save fails
      widget.onGroupCreated(group);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

// Rest of the existing functions remain the same...

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