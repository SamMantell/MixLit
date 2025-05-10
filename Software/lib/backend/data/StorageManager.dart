import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'package:yaml_writer/yaml_writer.dart';

class StorageManager {
  static final StorageManager _instance = StorageManager._internal();

  static StorageManager get instance => _instance;

  StorageManager._internal();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final mixlitDataDir = Directory('${directory.path}/MixLit/data');

    if (!await mixlitDataDir.exists()) {
      await mixlitDataDir.create(recursive: true);
    }

    print('Storage path: ${mixlitDataDir.path}');
    return mixlitDataDir.path;
  }

  Future<String> get _localFile async {
    final path = await _localPath;
    return '$path/mixlit.yml';
  }

  Future<void> saveData(String key, dynamic data) async {
    try {
      final file = File(await _localFile);
      print('Saving data to ${file.path}');

      Map<String, dynamic> existingData = {};
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          existingData =
              Map<String, dynamic>.from(yaml.loadYaml(contents) ?? {});
        }
      }

      existingData[key] = data;

      final yamlWriter = YamlWriter();
      final yamlString = yamlWriter.write(existingData);
      await file.writeAsString(yamlString);
    } catch (e) {
      print('Error saving data to storage: $e');
      rethrow;
    }
  }

  Future<dynamic> getData(String key, {dynamic defaultValue}) async {
    try {
      final file = File(await _localFile);

      if (!await file.exists()) {
        print('File does not exist, returning default value');
        return defaultValue;
      }

      final contents = await file.readAsString();
      if (contents.isEmpty) {
        print('File is empty, returning default value');
        return defaultValue;
      }

      final data = yaml.loadYaml(contents);
      final result =
          data != null && data[key] != null ? data[key] : defaultValue;
      return result;
    } catch (e) {
      print('Error reading data from storage: $e');
      return defaultValue;
    }
  }

  Future<void> removeData(String key) async {
    try {
      final file = File(await _localFile);
      if (!await file.exists()) {
        print('Cannot remove key $key - file does not exist');
        return;
      }

      final contents = await file.readAsString();
      Map<String, dynamic> existingData = {};
      if (contents.isNotEmpty) {
        existingData = Map<String, dynamic>.from(yaml.loadYaml(contents) ?? {});
      }

      existingData.remove(key);

      final yamlWriter = YamlWriter();
      await file.writeAsString(yamlWriter.write(existingData));
    } catch (e) {
      print('Error removing data from storage: $e');
      rethrow;
    }
  }

  Future<void> clearStorage() async {
    try {
      final file = File(await _localFile);
      if (await file.exists()) {
        await file.delete();
        print('Storage cleared - file deleted');
      }
    } catch (e) {
      print('Error clearing storage: $e');
      rethrow;
    }
  }

  Future<void> dumpStorageContents() async {
    try {
      final file = File(await _localFile);
      if (!await file.exists()) {
        print('Storage file does not exist');
        return;
      }

      final contents = await file.readAsString();
      if (contents.isEmpty) {
        print('Storage file is empty');
        return;
      }

      print('==== CONFIG CONTENTS ====');
      print(contents);
      print('==== END OF CONFIG CONTENTS ====');
    } catch (e) {
      print('Error dumping storage contents: $e');
    }
  }
}
