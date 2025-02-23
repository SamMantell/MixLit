import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'package:yaml_writer/yaml_writer.dart';

class StorageManager {
  static final StorageManager _instance = StorageManager._internal();
  factory StorageManager() => _instance;
  StorageManager._internal();

  // Singleton instance getter
  static StorageManager get instance => _instance;

  // Get the path to the data directory
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final mixlitDataDir = Directory('${directory.path}/data');

    // Create the directory if it doesn't exist
    if (!await mixlitDataDir.exists()) {
      await mixlitDataDir.create(recursive: true);
    }

    return mixlitDataDir.path;
  }

  // Get the full file path for mixlit.yml
  Future<String> get _localFile async {
    final path = await _localPath;
    return '$path/mixlit.yml';
  }

  // Save data to the YAML file
  Future<void> saveData(String key, dynamic data) async {
    try {
      final file = File(await _localFile);

      // Read existing data
      Map<String, dynamic> existingData = {};
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          existingData =
              Map<String, dynamic>.from(yaml.loadYaml(contents) ?? {});
        }
      }

      // Update or add new data
      existingData[key] = data;

      // Write updated data back to file
      final yamlWriter = YamlWriter();
      await file.writeAsString(yamlWriter.write(existingData));
    } catch (e) {
      print('Error saving data to storage: $e');
      rethrow;
    }
  }

  // Retrieve data from the YAML file
  Future<dynamic> getData(String key, {dynamic defaultValue}) async {
    try {
      final file = File(await _localFile);

      if (!await file.exists()) {
        return defaultValue;
      }

      final contents = await file.readAsString();
      if (contents.isEmpty) {
        return defaultValue;
      }

      final data = yaml.loadYaml(contents);
      return data != null && data[key] != null ? data[key] : defaultValue;
    } catch (e) {
      print('Error reading data from storage: $e');
      return defaultValue;
    }
  }

  // Remove a specific key from the storage
  Future<void> removeData(String key) async {
    try {
      final file = File(await _localFile);

      if (!await file.exists()) {
        return;
      }

      final contents = await file.readAsString();
      Map<String, dynamic> existingData = {};

      if (contents.isNotEmpty) {
        existingData = Map<String, dynamic>.from(yaml.loadYaml(contents) ?? {});
      }

      // Remove the specified key
      existingData.remove(key);

      // Write updated data back to file
      final yamlWriter = YamlWriter();
      await file.writeAsString(yamlWriter.write(existingData));
    } catch (e) {
      print('Error removing data from storage: $e');
      rethrow;
    }
  }

  // Clear entire storage
  Future<void> clearStorage() async {
    try {
      final file = File(await _localFile);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error clearing storage: $e');
      rethrow;
    }
  }
}
