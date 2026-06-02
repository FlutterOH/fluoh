import 'package:args/args.dart';

/// Callback used by command validators to report usage errors.
typedef UsageError = Never Function(String message);

/// Fails when a command receives positional arguments.
void expectNoArguments(ArgResults results, UsageError usageException) {
  final rest = results.rest;
  if (rest.isEmpty) {
    return;
  }

  if (rest.length == 1) {
    usageException('Unexpected argument: ${rest.single}.');
  }
  usageException('Unexpected arguments: ${rest.join(' ')}.');
}

/// Returns exactly [count] positional arguments or fails with [message].
List<String> expectArgumentCount(
  ArgResults results,
  int count,
  String message,
  UsageError usageException,
) {
  final rest = results.rest;
  if (rest.length != count) {
    usageException(message);
  }
  return rest;
}

/// Returns positional arguments when there are at most [count].
List<String> expectArgumentCountAtMost(
  ArgResults results,
  int count,
  String message,
  UsageError usageException,
) {
  final rest = results.rest;
  if (rest.length > count) {
    usageException(message);
  }
  return rest;
}
