import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/fluoh_installation.dart';

typedef UpgradeProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef UpgradeScriptUriProvider = Uri Function();

class UpgradeCommand extends Command<int> {
  UpgradeCommand({
    required OutputWriter stdout,
    OutputWriter? stderr,
    UpgradeProcessRunner? processRunner,
    UpgradeScriptUriProvider? scriptUriProvider,
  }) : _stdout = stdout,
       _stderr = stderr ?? stdout,
       _processRunner =
           processRunner ??
           ((executable, arguments) => Process.run(executable, arguments)),
       _scriptUriProvider = scriptUriProvider ?? (() => Platform.script) {
    argParser.addFlag(
      'yes',
      negatable: false,
      help: 'Execute the fluoh self-upgrade command.',
    );
  }

  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final UpgradeProcessRunner _processRunner;
  final UpgradeScriptUriProvider _scriptUriProvider;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade the fluoh CLI tool itself.';

  @override
  Future<int> run() async {
    final plan = _resolveUpgradePlan(_scriptUriProvider());

    if (!argResults!.flag('yes')) {
      if (plan.refusalMessage != null) {
        _stdout(plan.refusalMessage!);
        return 0;
      }
      _stdout('Upgrade command: ${plan.displayCommand}');
      _stdout('Run with --yes to execute.');
      return 0;
    }

    if (plan.refusalMessage != null) {
      _stderr(plan.refusalMessage!);
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
    required this.displayCommand,
    this.refusalMessage,
  });

  final String executable;
  final List<String> arguments;
  final String displayCommand;
  final String? refusalMessage;
}

_UpgradePlan _resolveUpgradePlan(Uri scriptUri) {
  final installation = resolveFluohInstallation(scriptUri);
  switch (installation.method) {
    case FluohInstallMethod.homebrew:
      return const _UpgradePlan(
        executable: 'brew',
        arguments: ['upgrade', 'fluoh'],
        displayCommand: 'brew upgrade fluoh',
      );
    case FluohInstallMethod.localSourceCheckout:
      return const _UpgradePlan(
        executable: 'dart',
        arguments: ['pub', 'global', 'activate', 'fluoh'],
        displayCommand: 'dart pub global activate fluoh',
        refusalMessage:
            'Local source checkouts cannot be upgraded automatically. '
            'Run `dart pub global activate fluoh --overwrite` if you want to '
            'replace the local checkout with the pub.dev release.',
      );
    case FluohInstallMethod.dartPubGlobal:
      return const _UpgradePlan(
        executable: 'dart',
        arguments: ['pub', 'global', 'activate', 'fluoh'],
        displayCommand: 'dart pub global activate fluoh',
      );
  }
}
