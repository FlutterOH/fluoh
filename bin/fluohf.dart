import 'dart:io' as io;

import 'package:fluoh/fluoh.dart';

Future<void> main(List<String> arguments) async {
  io.exitCode = await runFluohFlutter(arguments);
}
