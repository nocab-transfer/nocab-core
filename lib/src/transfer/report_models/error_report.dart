part of report_models;

class ErrorReport extends Report {
  CoreError error;

  ErrorReport({
    required this.error,
  });
}
