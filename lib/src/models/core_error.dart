class CoreError {
  final String title;
  final Object? error;
  final String className;
  final String methodName;
  final StackTrace stackTrace;

  CoreError(this.title, {this.error, required this.stackTrace, required this.className, required this.methodName});

  CoreError.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        error = json['error'],
        className = json['className'],
        methodName = json['methodName'],
        stackTrace = StackTrace.fromString(json['stackTrace']);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'error': error.toString(),
        'className': className,
        'methodName': methodName,
        'stackTrace': stackTrace.toString(),
      };

  @override
  String toString() {
    return 'CoreError{title: $title, error: $error, className: $className, methodName: $methodName, stackTrace: $stackTrace}';
  }
}
