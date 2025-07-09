import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mixlit/frontend/menus/dialog/Update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:version/version.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;

class Updater {
  static const String _githubApiUrl =
      'https://api.github.com/repos/SamMantell/MixLit/releases/latest';
  static const String _githubReleasesUrl =
      'https://github.com/SamMantell/MixLit/releases/latest';

  //IMPORTANT: set to false during development, but remember to set back to true before going live lol
  static const bool _updateEnabled = true;

  static final Updater _instance = Updater._internal();
  factory Updater() => _instance;
  Updater._internal();

  bool _isCheckingForUpdates = false;

  Future<UpdateInfo?> checkForUpdates() async {
    if (!_updateEnabled || _isCheckingForUpdates) return null;

    _isCheckingForUpdates = true;
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = Version.parse(packageInfo.version);

      final http.Response response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        _isCheckingForUpdates = false;
        return null;
      }

      final Map<String, dynamic> releaseData = json.decode(response.body);

      String tagName = releaseData['tag_name'] as String;
      if (tagName.startsWith('v')) {
        tagName = tagName.substring(1);
      }

      final latestVersion = Version.parse(tagName);

      String? installerUrl;
      String? installerFileName;

      for (var asset in releaseData['assets'] as List) {
        final assetName = asset['name'] as String;
        if (assetName.contains('MixLit-Installer') &&
            assetName.endsWith('.exe')) {
          installerUrl = asset['browser_download_url'] as String;
          installerFileName = assetName;
          break;
        }
      }

      final bool hasUpdate = latestVersion > currentVersion;
      final DateTime publishedAt =
          DateTime.parse(releaseData['published_at'] as String);

      _isCheckingForUpdates = false;

      if (hasUpdate && installerUrl != null) {
        return UpdateInfo(
          currentVersion: currentVersion.toString(),
          latestVersion: latestVersion.toString(),
          releaseDate: publishedAt,
          changelog: releaseData['body'] as String? ?? 'No changelog provided.',
          downloadUrl: installerUrl,
          fileName: installerFileName!,
        );
      }

      return null;
    } catch (e) {
      print('Error checking for updates: $e');
      _isCheckingForUpdates = false;
      return null;
    }
  }

  Future<bool> downloadAndInstallUpdate(
      UpdateInfo updateInfo, Function(double) onProgress) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(tempDir.path, updateInfo.fileName);

      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(updateInfo.downloadUrl));
      final response = await http.Client().send(request);

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      final sink = file.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;

        if (contentLength > 0) {
          onProgress(received / contentLength);
        }
      });

      await sink.close();
      return _launchInstaller(filePath);
    } catch (e) {
      print('Error downloading update: $e');
      return false;
    }
  }

  // launch installer, then exit
  Future<bool> _launchInstaller(String filePath) async {
    try {
      final uri = Uri.file(filePath);

      if (await canLaunchUrl(uri)) {
        // run installer with admin
        final process = await Process.start(
          'cmd.exe',
          ['/c', 'start', '', '/wait', filePath],
          mode: ProcessStartMode.detached,
        );

        Future.delayed(const Duration(milliseconds: 500), () {
          exit(0);
        });

        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('Error launching installer: $e');
      return false;
    }
  }

  Future<void> openReleasesPage() async {
    final uri = Uri.parse(_githubReleasesUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Shows the update dialog
  Future<bool?> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
    return UpdateDialog.show(
      context: context,
      updateInfo: updateInfo,
      onProgressUpdate: (progress) {},
      onUpdateNow: () async {
        await downloadAndInstallUpdate(updateInfo, (progress) {});
      },
    );
  }

  Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    final updateInfo = await checkForUpdates();
    if (updateInfo != null && context.mounted) {
      showUpdateDialog(context, updateInfo);
    }
  }
}
