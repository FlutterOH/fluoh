import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/fluoh_installation.dart';
import '../cli/terminal_output.dart';

typedef UpgradeProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef UpgradeScriptUriProvider = Uri Function();

class UpgradeCommand extends Command<int> {
  UpgradeCommand({
    required OutputWriter stdout,
    OutputWriter? stderr,
    TerminalOutput? output,
    UpgradeProcessRunner? processRunner,
    UpgradeScriptUriProvider? scriptUriProvider,
  }) : _stdout = stdout,
       _stderr = stderr ?? stdout,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr),
       _processRunner =
           processRunner ??
           ((executable, arguments) => Process.run(executable, arguments)),
       _scriptUriProvider = scriptUriProvider ?? (() => Platform.script);

  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;
  final UpgradeProcessRunner _processRunner;
  final UpgradeScriptUriProvider _scriptUriProvider;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade the fluoh CLI tool itself.';

  @override
  Future<int> run() async {
    final plan = _resolveUpgradePlan(_scriptUriProvider());

    if (plan.refusalMessage != null) {
      _output.error(plan.refusalMessage!);
      return 64;
    }

    final result = await _processRunner(plan.executable, plan.arguments);
    if (result.stdout.toString().trim().isNotEmpty) {
      _stdout(result.stdout.toString().trimRight());
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      _stderr(result.stderr.toString().trimRight());
    }

    return result.exitCode;
  }
}

class _UpgradePlan {
  const _UpgradePlan({
    required this.executable,
    required this.arguments,
    this.refusalMessage,
  });

  final String executable;
  final List<String> arguments;
  final String? refusalMessage;
}

_UpgradePlan _resolveUpgradePlan(Uri scriptUri) {
  final installation = resolveFluohInstallation(scriptUri);
  switch (installation.method) {
    case FluohInstallMethod.homebrew:
      return const _UpgradePlan(
        executable: 'brew',
        arguments: ['upgrade', 'fluoh'],
      );
    case FluohInstallMethod.localSourceCheckout:
      return const _UpgradePlan(
        executable: 'dart',
        arguments: ['pub', 'global', 'activate', 'fluoh'],
        refusalMessage:
            'Local source checkouts cannot be upgraded automatically. '
            'Run `dart pub global activate fluoh --overwrite` if you want to '
            'replace the local checkout with the pub.dev release.',
      );
    case FluohInstallMethod.dartPubGlobal:
      return const _UpgradePlan(
        executable: 'dart',
        arguments: ['pub', 'global', 'activate', 'fluoh'],
      );
  }
}
