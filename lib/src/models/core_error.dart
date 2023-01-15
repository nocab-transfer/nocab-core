class CoreError {
  final String title;
  final Object? error;
  final String className;
  final String methodName;
  final StackTrace stackTrace;

  CoreError(this.title, {this.error, required this.stackTrace, required this.className, required this.methodName});
}
