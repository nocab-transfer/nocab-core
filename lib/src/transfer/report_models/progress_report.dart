part of report_models;

class ProgressReport extends Report {
  List<FileInfo> filesTransferred;
  FileInfo currentFile;
  double speed;
  double progress;

  ProgressReport({
    required this.filesTransferred,
    required this.currentFile,
    required this.speed,
    required this.progress,
  });
}
