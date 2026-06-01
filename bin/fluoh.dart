import 'dart:io' as io;

import 'package:fluoh/fluoh.dart';

Future<void> main(List<String> arguments) async {
  final exitCode = await runFluoh(arguments);
  await io.stdout.flush();
  await io.stderr.flush();
  io.exit(exitCode);
}
