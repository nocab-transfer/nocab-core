import 'dart:io';
import 'dart:isolate';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart';

class FileOperations {
  static tmpToFile(File file, String newPath) async {
    await file.copy(newPath);
    await file.delete();
  }

  static String findUnusedFilePath({required String fileName, required String downloadPath}) {
    int fileIndex = 0;
    String path;

    do {
      path = join(downloadPath, withoutExtension(fileName) + (fileIndex > 0 ? " ($fileIndex)" : "") + extension(fileName));
      fileIndex++;
    } while (File(path).existsSync());

    return path;
  }

  static Future<List<FileInfo>> convertPathsToFileInfos(List<String> paths) async {
    // create a list contains all directories
    List<Directory> directoryList = paths.where((element) => Directory(element).existsSync()).map((e) => Directory(e)).toList();

    // create a list contains all files
    List<FileInfo> files = [];
    for (var filePath in paths.where((path) => File(path).existsSync())) {
      files.add(FileInfo.fromFile(File(filePath)));
    }

    // add files under directories
    await Future.forEach(directoryList, (dir) async => files.addAll(await FileOperations.getFilesUnderDirectory(dir.path)));
    return files;
  }

  static Future<List<FileInfo>> getFilesUnderDirectory(String path, [String? parentSubDirectory]) async {
    // open new thread to reduce cpu load
    return await Isolate.run(() => _getFilesUnderDirectory(path, parentSubDirectory));
  }

  static Future<List<FileInfo>> _getFilesUnderDirectory(String path, String? parentSubDirectory) async {
    var filesUnderDirectory = await Directory(path).list().toList();

    var files = <FileInfo>[];

    await Future.forEach(filesUnderDirectory, (element) async {
      String subDirectory = basename(path);

      switch ((await element.stat()).type) {
        case FileSystemEntityType.file:
          var file = File(element.path);
          files.add(FileInfo.fromFile(file, subDirectory: join(parentSubDirectory ?? "", subDirectory)));
          break;
        case FileSystemEntityType.directory:
          var subDirectoryFiles = await _getFilesUnderDirectory(element.path, join(parentSubDirectory ?? "", subDirectory));
          files.addAll(subDirectoryFiles);
          break;
        default:
      }
    });

    return files;
  }
}
