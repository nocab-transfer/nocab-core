import 'dart:io';
import 'dart:isolate';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart';

class FileOperations {
  /// Finds a file path that doesn't exist in the given [downloadPath] and
  /// returns the path to it.
  ///
  /// It does this by checking if a file with the given [fileName] exists in
  /// [downloadPath] and, if so, adding a number in parentheses after the file
  /// name. For example, if "file.png" already exists in the download path, then
  /// this function will return "file (1).png". If "file (1).png" already
  /// exists, then it will return "file (2).png", and so on.
  ///
  /// This function will not return a file path that already exists.
  ///
  /// Parameters:
  ///   * [fileName]: The name of the file whose file path is being searched for.
  ///   * [downloadPath]: The path to the directory in which the file is being
  ///     searched for.
  ///
  /// Returns:
  ///   A file path that doesn't exist in the given [downloadPath].
  static String findUnusedFilePath({required String fileName, required String downloadPath}) {
    int fileIndex = 0;
    String path;

    do {
      path = join(downloadPath, withoutExtension(fileName) + (fileIndex > 0 ? " ($fileIndex)" : "") + extension(fileName));
      fileIndex++;
    } while (File(path).existsSync());

    return path;
  }

  /// This function will return a list of [FileInfo] from a string list of [paths]
  ///
  /// It will also include files under directories if [includeFilesUnderDirectories] is true
  static Future<List<FileInfo>> convertPathsToFileInfos(List<String> paths, {bool includeFilesUnderDirectories = true}) async {
    // create a list contains all files
    List<FileInfo> files = [];
    for (var filePath in paths.where((path) => File(path).existsSync())) {
      files.add(FileInfo.fromFile(File(filePath)));
    }

    if (includeFilesUnderDirectories) {
      // create a list contains all directories
      List<Directory> directoryList = paths.where((element) => Directory(element).existsSync()).map((e) => Directory(e)).toList();

      // add files under directories
      await Future.forEach(directoryList, (dir) async => files.addAll(await FileOperations.getFilesUnderDirectory(dir.path)));
    }

    return files;
  }

  /// Returns a list of files under the given directory
  ///
  /// [path] is the path of the directory
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
