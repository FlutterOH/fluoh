import 'package:args/args.dart';

typedef UsageError = Never Function(String message);

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
