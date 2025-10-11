import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';

class AppGroup {
  final String id;
  final String name;
  final List<String> processNames;
  final Color color;
  final DateTime createdAt;
  final String? iconData;

  AppGroup({
    required this.id,
    required this.name,
    required this.processNames,
    required this.color,
    required this.createdAt,
    this.iconData,
  });

  AppGroup copyWith({
    String? id,
    String? name,
    List<String>? processNames,
    Color? color,
    DateTime? createdAt,
    String? iconData,
  }) {
    return AppGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      processNames: processNames ?? this.processNames,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      iconData: iconData ?? this.iconData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'processNames': processNames,
      'color': color.value,
      'createdAt': createdAt.toIso8601String(),
      if (iconData != null) 'iconData': iconData,
    };
  }

  factory AppGroup.fromJson(Map<String, dynamic> json) {
    return AppGroup(
      id: json['id'],
      name: json['name'],
      processNames: List<String>.from(json['processNames']),
      color: Color(json['color']),
      createdAt: DateTime.parse(json['createdAt']),
      iconData: json['iconData'],
    );
  }
}

Future<List<AudioSessionInfo?>> assignApplication(
  BuildContext context,
  int sliderIndex,
  ApplicationManager applicationManager,
  List<AudioSessionInfo?> assignedApps,
  Map<String, Uint8List?> appIcons,
  List<double> sliderValues,
  List<String> sliderTags,
) async {
  final runningApps =
      await applicationManager.getRunningApplicationsWithAudio();
  await fetchAllAppIcons(
    runningApps,
    appIcons,
    audioServiceClient: applicationManager.audioServiceClient,
  );

  final previousTag = sliderTags[sliderIndex];
  final previousApp = assignedApps[sliderIndex];

  final availableApps = runningApps.where((app) {
    final hasIcon = appIcons[app.processPath] != null;
    final hasValidName = app.processName.isNotEmpty &&
        app.processName.toLowerCase() != 'unknown' &&
        app.processPath.isNotEmpty;

    if (!hasIcon && !hasValidName) {
      return false;
    }

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
              length: 3,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: MediaQuery.of(context).size.height * 0.7,
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
                                          errorBuilder:
                                              (context, error, stack) =>
                                                  const Icon(Icons.apps,
                                                      color: Colors.white),
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
                  (MediaQuery.of(context).size.height * 0.48) +
                  90,
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
        final app = result['app'] as AudioSessionInfo;
        assignedApps[sliderIndex] = app;
        sliderTags[sliderIndex] = ConfigManager.TAG_APP;
        await applicationManager.assignApplicationToSlider(sliderIndex, app);
        break;

      case 'group':
        final group = result['group'] as AppGroup;
        assignedApps[sliderIndex] = null;
        sliderTags[sliderIndex] = ConfigManager.TAG_GROUP;
        await applicationManager.assignGroupToSlider(sliderIndex, group);
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

class GroupsTabContent extends StatefulWidget {
  final List<AudioSessionInfo> availableApps;
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
  AppGroup? editingGroup;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedGroups();
  }

  Future<void> _loadSavedGroups() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final configManager = ConfigManager.instance;
      final groups = await configManager.loadAppGroups();
      print(
          'Loaded ${groups.length} groups from storage'); // ADD THIS DEBUG LINE

      if (mounted) {
        setState(() {
          savedGroups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading saved groups: $e');
      if (mounted) {
        setState(() {
          savedGroups = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteGroup(AppGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkMode
            ? const Color(0xFF2A2A2A)
            : const Color.fromARGB(255, 240, 240, 240),
        title: Text(
          'Delete Group',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            color: widget.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${group.name}"?',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            color: widget.isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final configManager = ConfigManager.instance;
        await configManager.deleteAppGroup(group.id);
        setState(() {
          savedGroups.removeWhere((g) => g.id == group.id);
        });
      } catch (e) {
        print('Error deleting group: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isCreatingGroup || editingGroup != null) {
      return GroupCreationWidget(
        availableApps: widget.availableApps,
        appIcons: widget.appIcons,
        isDarkMode: widget.isDarkMode,
        existingGroup: editingGroup,
        onGroupCreated: (group) async {
          setState(() {
            if (editingGroup != null) {
              // Update existing group
              final index = savedGroups.indexWhere((g) => g.id == group.id);
              if (index != -1) {
                savedGroups[index] = group;
              }
            } else {
              // Add new group
              savedGroups.add(group);
            }
            isCreatingGroup = false;
            editingGroup = null;
          });
        },
        onCancel: () {
          setState(() {
            isCreatingGroup = false;
            editingGroup = null;
          });
        },
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit,
                                color: Colors.white70, size: 20),
                            onPressed: () {
                              setState(() {
                                editingGroup = group;
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.red, size: 20),
                            onPressed: () => _deleteGroup(group),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(
                            context, {'type': 'group', 'group': group});
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class GroupCreationWidget extends StatefulWidget {
  final List<AudioSessionInfo> availableApps;
  final Map<String, Uint8List?> appIcons;
  final bool isDarkMode;
  final Function(AppGroup) onGroupCreated;
  final VoidCallback onCancel;
  final AppGroup? existingGroup;

  const GroupCreationWidget({
    super.key,
    required this.availableApps,
    required this.appIcons,
    required this.isDarkMode,
    required this.onGroupCreated,
    required this.onCancel,
    this.existingGroup,
  });

  @override
  State<GroupCreationWidget> createState() => _GroupCreationWidgetState();
}

class _GroupCreationWidgetState extends State<GroupCreationWidget> {
  late TextEditingController _nameController;
  late Set<String> _selectedApps;
  late Color _selectedColor;

  final Map<String, Uint8List?> _inactiveAppIcons = {};

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
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingGroup?.name ?? '',
    );
    _selectedApps = widget.existingGroup?.processNames.toSet() ?? {};
    _selectedColor = widget.existingGroup?.color ?? Colors.blue;

    _loadInactiveAppIcons();
  }

  Future<void> _loadInactiveAppIcons() async {
    if (widget.existingGroup == null) return;

    final configManager = ConfigManager.instance;

    for (final processName in widget.existingGroup!.processNames) {
      // Check if this app is not in the active apps list
      final isActive = widget.availableApps
          .any((app) => app.processPath.split(r'\').last == processName);

      if (!isActive) {
        // load cached icon
        try {
          final cachedIconPath =
              await configManager.getCachedIconByProcessName(processName);
          if (cachedIconPath != null) {
            final iconFile = File(cachedIconPath);
            if (await iconFile.exists()) {
              final iconData = await iconFile.readAsBytes();
              if (mounted) {
                setState(() {
                  _inactiveAppIcons[processName] = iconData;
                });
              }
            }
          }
        } catch (e) {
          print('Error loading cached icon for $processName: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingGroup != null;

    final Map<String, AudioSessionInfo?> allApps = {};

    for (final app in widget.availableApps) {
      final processName = app.processPath.split(r'\').last;
      allApps[processName] = app;
    }

    if (widget.existingGroup != null) {
      for (final processName in widget.existingGroup!.processNames) {
        if (!allApps.containsKey(processName)) {
          allApps[processName] = null;
        }
      }
    }

    // Sort apps: active first, then inactive
    final sortedAppEntries = allApps.entries.toList()
      ..sort((a, b) {
        if (a.value != null && b.value == null) return -1;
        if (a.value == null && b.value != null) return 1;
        return _formatAppName(a.key).compareTo(_formatAppName(b.key));
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: widget.onCancel,
            ),
            Text(
              isEditing ? 'Edit Group' : 'Create New Group',
              style: const TextStyle(
                fontFamily: 'BitstreamVeraSans',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
        const Text(
          'Group Colour:',
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
        Row(
          children: [
            const Text(
              'Select Applications:',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_selectedApps.length} selected)',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: sortedAppEntries.length,
            itemBuilder: (context, index) {
              final entry = sortedAppEntries[index];
              final processName = entry.key;
              final app = entry.value; // null if inactive
              final appName = _formatAppName(processName);
              final isActive = app != null;
              final isSelected = _selectedApps.contains(processName);

              Uint8List? iconData;
              if (isActive) {
                iconData = widget.appIcons[app.processPath];
              } else {
                iconData = _inactiveAppIcons[processName];
              }

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
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        appName,
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: isActive
                              ? Colors.white
                              : Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                    if (!isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 241, 199, 137)
                              .withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color.fromARGB(255, 226, 178, 105)
                                .withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Closed',
                          style: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            color: const Color.fromARGB(255, 255, 227, 152)
                                .withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                secondary: iconData != null
                    ? Opacity(
                        opacity: isActive ? 1.0 : 0.5,
                        child: Image.memory(
                          iconData,
                          width: 32,
                          height: 32,
                          errorBuilder: (context, error, stack) => Icon(
                            Icons.apps,
                            color: isActive
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.apps,
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                      ),
                activeColor: _selectedColor,
                checkColor: Colors.white,
                // Dim the entire tile if inactive
                tileColor: isActive ? null : Colors.black.withOpacity(0.2),
              );
            },
          ),
        ),
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
            child: Text(
              isEditing ? 'Save Changes' : 'Create Group',
              style: const TextStyle(
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
      id: widget.existingGroup?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      processNames: _selectedApps.toList(),
      color: _selectedColor,
      createdAt: widget.existingGroup?.createdAt ?? DateTime.now(),
    );

    try {
      final configManager = ConfigManager.instance;
      await configManager.saveAppGroup(group);
      widget.onGroupCreated(group);
    } catch (e) {
      print('Error saving group: $e');
      widget.onGroupCreated(group);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

String _formatAppName(String appName) {
  appName = appName.replaceAll('.exe', '');

  if (appName.isEmpty) {
    return 'Unknown';
  }

  return appName[0].toUpperCase() + appName.substring(1);
}

Future<void> fetchAllAppIcons(
    List<AudioSessionInfo> apps, Map<String, Uint8List?> appIcons,
    {AudioServiceClient? audioServiceClient}) async {
  for (var app in apps) {
    if (!appIcons.containsKey(app.processPath) ||
        appIcons[app.processPath] == null) {
      if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
        try {
          appIcons[app.processPath] = base64Decode(app.iconBase64!);
          continue;
        } catch (e) {
          print('Error decoding icon for ${app.processPath}: $e');
        }
      }

      if (audioServiceClient != null) {
        try {
          final iconBase64 = await audioServiceClient.getIcon(app.processPath);
          if (iconBase64 != null && iconBase64.isNotEmpty) {
            appIcons[app.processPath] = base64Decode(iconBase64);
            continue;
          }
        } catch (e) {
          print('Error fetching icon from service for ${app.processPath}: $e');
        }
      }

      appIcons[app.processPath] = null;
    }
  }
}
