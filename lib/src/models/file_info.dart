import 'dart:io';

import 'package:path/path.dart';

class FileInfo {
  late String name;
  late int byteSize;
  late bool isEncrypted;
  String? path; //local
  String? hash;
  String? subDirectory;

  bool get exist => File(path ?? "").existsSync();

  FileInfo({required this.name, required this.byteSize, required this.isEncrypted, this.hash, this.path, this.subDirectory});

  FileInfo.fromFile(File file, {this.isEncrypted = false, this.subDirectory}) {
    name = basename(file.path);
    byteSize = file.lengthSync();
    path = file.path;
  }

  FileInfo.fromJson(Map<String, dynamic> json) {
    name = json['name'];
    byteSize = json['byteSize'];
    isEncrypted = json['isEncrypted'];
    hash = json['hash'];
    subDirectory = json['subDirectory'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['byteSize'] = byteSize;
    data['isEncrypted'] = isEncrypted;
    data['hash'] = hash;
    data['subDirectory'] = subDirectory;
    return data;
  }
}
