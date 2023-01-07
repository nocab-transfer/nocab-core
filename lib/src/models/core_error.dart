class CoreError {
  final String message;
  final StackTrace stackTrace;
  final String className;
  final String methodName;

  CoreError(this.message, {required this.stackTrace, required this.className, required this.methodName});
}
