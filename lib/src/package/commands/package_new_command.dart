import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../platform/platform_environment.dart';
import '../../schema/schema.dart';
import '../../sdk/flutter_runner.dart';
import '../../sdk/sdk_manager.dart';
import '../../sdk/sdk_project_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_repository_docs.dart';
import '../package_spec.dart';
import '../repository_url.dart';

/// Creates a spec-first FlutterOH package repository.
class PackageNewCommand extends FluohCommand<int> {
  /// Creates the package new command.
  PackageNewCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'output',
        valueHelp: 'path',
        help: 'Destination path for the FlutterOH package repository.',
      )
      ..addOption(
        'repository-name',
        valueHelp: 'repository-name',
        help:
            'FlutterOH package repository name for the default output path and repository URL. Defaults to <name>.',
      )
      ..addOption(
        'sdk',
        valueHelp: 'version-or-series',
        help: 'FlutterOH SDK version or version series.',
      )
      ..addOption(
        'repository',
        abbr: 'r',
        valueHelp: 'url',
        help: 'Final FlutterOH package repository URL for origin and manifest.',
      )
      ..addOption(
        'org',
        valueHelp: 'organization',
        help: 'Organization passed to flutter create.',
      )
      ..addOption(
        'template',
        valueHelp: 'template',
        defaultsTo: 'plugin',
        allowed: const ['plugin', 'package'],
        help: 'Flutter template used to create the package skeleton.',
      )
      ..addOption(
        'platforms',
        valueHelp: 'platforms',
        defaultsTo: 'ohos',
        help: 'Comma-separated platforms passed to flutter create.',
      )
      ..addOption(
        'git-author-name',
        valueHelp: 'name',
        help: 'Configure local Git user.name for generated commits.',
      )
      ..addOption(
        'git-author-email',
        valueHelp: 'email',
        help: 'Configure local Git user.email for generated commits.',
      )
      ..addFlag(
        'plan',
        negatable: false,
        help: 'Print the package creation plan without writing files.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the package creation plan as JSON. Requires --plan.',
      );
  }

  /// Runtime environment for SDK, Git, and filesystem operations.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'new';

  @override
  String get description => 'Create a new FlutterOH package repository.';

  @override
  String get invocation => 'fluoh package new <name>';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  @override
  Future<int> run() async {
    final planOnly = argResults!.flag('plan');
    final json = argResults!.flag('json');
    if (json && !planOnly) {
      usageException('--json is supported only with --plan for package new.');
    }
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <name>: Dart package name.',
      usageException,
    );
    final packageName = rest.single.trim();
    validateDartPackageName(packageName, label: '<name>');
    final repositoryName = _repositoryNameFromOptions(packageName);
    final repositoryUrl =
        argResults!.option('repository') ??
        defaultPackageRepositoryUrl(repositoryName);
    final destination = _destination(repositoryName);
    final release = await _resolveSdkRelease(allowUnindexedExact: planOnly);
    final branch = flutterOhosPackageBranchForSdk(
      sdkVersion: release.tag,
      packageName: packageName,
    );
    final gitAuthor = _gitAuthorConfigFromOptions();
    final template = argResults!.option('template')!;
    final platforms = _platformsFromOptions();
    final org = _flutterCreateOrgFromOptions();

    final plan = _PackageNewPlan(
      packageName: packageName,
      repositoryName: repositoryName,
      repositoryUrl: repositoryUrl,
      outputPath: destination.path,
      sdkVersion: release.tag,
      sdkLine: sdkLineFromSdkVersion(release.tag),
      branch: branch,
      template: template,
      platforms: platforms,
      flutterCreateOrg: org,
      gitAuthor: gitAuthor,
    );
    if (planOnly) {
      return _writePlan(plan, json: json);
    }
    if (await destination.exists()) {
      usageException('Destination already exists: ${destination.path}');
    }

    await destination.parent.create(recursive: true);
    var shouldRollbackDestination = true;
    try {
      final sdkDirectory = await _installSdk(release);
      await _initializeCreatedRepositoryIndex(
        destination: destination,
        repositoryName: repositoryName,
        packageName: packageName,
        packageBranch: branch,
        repositoryUrl: repositoryUrl,
        gitAuthor: gitAuthor,
      );
      await runGit(['checkout', '-b', branch], workingDirectory: destination);
      final mainReadme = File('${destination.path}/README.md');
      if (await mainReadme.exists()) {
        await mainReadme.delete();
      }
      await _runFlutterCreate(
        destination: destination,
        sdkDirectory: sdkDirectory,
        packageName: packageName,
        template: template,
        platforms: platforms,
        org: org,
      );
      final package = await readPubspecPackage(
        destination,
        description: 'generated package',
      );
      if (package.name != packageName) {
        usageException(
          'flutter create generated package ${package.name}, expected $packageName.',
        );
      }
      await _ensureCreatedPackageReadme(destination, packageName);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: destination,
        processEnvironment: environment.processEnvironment,
      );
      await SdkProjectEnvironment(packageEnvironment).linkIdeSdk(sdkDirectory);
      final manifest = createSpecPackageManifest(
        package: package,
        packagePath: '.',
        sdkVersion: release.tag,
        branch: branch,
        repositoryUrl: repositoryUrl,
        releaseVersion: package.version,
        status: 'experimental',
      );
      await writePackageManifestFile(destination, manifest);
      await writeInitialPackageSpec(
        repository: destination,
        manifest: manifest,
      );
      await writeOrReplacePackageContext(
        destination: destination,
        packages: packageRepositoryDocPackagesForManifest(manifest),
      );
      await runGit(['add', '-A'], workingDirectory: destination);

      _output.success(
        'Created FlutterOH package repository at ${_output.style.path(destination.path)}',
      );
      _output.info('Package branch: $branch');
      _output.info('Repository: ${_output.style.url(repositoryUrl)}');
      _output.success('Configured FlutterOH SDK ${release.tag}');
      _output.next(
        'Implement the package API and platform behavior, then run fluoh package next --json',
      );
      shouldRollbackDestination = false;
      return 0;
    } catch (_) {
      if (shouldRollbackDestination && await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<SdkRelease> _resolveSdkRelease({
    required bool allowUnindexedExact,
  }) async {
    final manager = SdkManager(environment);
    final sdk = argResults!.option('sdk');
    if (sdk != null) {
      return manager.resolveRelease(
        sdk,
        allowUnindexedExact: allowUnindexedExact,
      );
    }
    final releases = await manager.listReleases();
    if (releases.isEmpty) {
      usageException('No SDK versions found in configured sources.');
    }
    return SdkManager.latestRelease(releases, preferStable: true);
  }

  Future<Directory> _installSdk(SdkRelease release) async {
    final manager = SdkManager(environment);
    final installed = await manager.sdkDirectory(release.tag).exists();
    return _output.withProgress(
      installed
          ? 'Using FlutterOH SDK ${release.tag}'
          : 'Installing FlutterOH SDK ${release.tag}; this may take a while.',
      () => manager.install(release),
      showWhenPlain: true,
    );
  }

  Future<void> _initializeCreatedRepositoryIndex({
    required Directory destination,
    required String repositoryName,
    required String packageName,
    required String packageBranch,
    required String repositoryUrl,
    required PackageGitAuthor? gitAuthor,
  }) async {
    await destination.create(recursive: true);
    await runGit([
      'init',
      '--quiet',
      '--initial-branch=main',
    ], workingDirectory: destination);
    await runGit([
      'remote',
      'add',
      'origin',
      repositoryUrl,
    ], workingDirectory: destination);
    if (gitAuthor != null) {
      await configurePackageGitAuthor(destination, gitAuthor);
    }
    await writePackageRepositoryIndexReadme(
      destination: destination,
      repositoryName: repositoryName,
      packageName: packageName,
      packageBranch: packageBranch,
    );
    await runGit(['add', 'README.md'], workingDirectory: destination);
    final commitArguments = gitAuthor == null
        ? [
            '-c',
            'user.name=fluoh',
            '-c',
            'user.email=fluoh@example.invalid',
            'commit',
            '-m',
            'Initialize FlutterOH package repository index',
          ]
        : ['commit', '-m', 'Initialize FlutterOH package repository index'];
    await runGit(commitArguments, workingDirectory: destination);
  }

  Future<void> _ensureCreatedPackageReadme(
    Directory destination,
    String packageName,
  ) async {
    final readme = File('${destination.path}/README.md');
    if (await readme.exists()) {
      return;
    }
    await readme.writeAsString('# $packageName\n');
  }

  Future<void> _runFlutterCreate({
    required Directory destination,
    required Directory sdkDirectory,
    required String packageName,
    required String template,
    required String platforms,
    required String? org,
  }) async {
    final flutter = File('${sdkDirectory.path}/bin/flutter');
    final arguments = [
      'create',
      '--template=$template',
      '--platforms=$platforms',
      '--project-name',
      packageName,
      if (org != null) ...['--org', org],
      destination.path,
    ];
    final process = await Process.start(
      flutter.path,
      arguments,
      workingDirectory: destination.parent.path,
      environment: selectedToolProcessEnvironment(
        environment: environment,
        tool: flutter,
      ),
    );
    final stdoutDone = process.stdout
        .transform(systemEncoding.decoder)
        .forEach(_stdout);
    final stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .forEach(_stderr);
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (exitCode != 0) {
      usageException('flutter create failed with exit code $exitCode.');
    }
  }

  int _writePlan(_PackageNewPlan plan, {required bool json}) {
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'package new',
        ok: true,
        exitCode: 0,
        fields: {'changed': false, 'applied': false, 'plan': plan.toJson()},
      );
      return 0;
    }
    _output.success('Package creation plan');
    _output.info('Package: ${plan.packageName}');
    _output.info('Repository name: ${plan.repositoryName}');
    _output.info('Output path: ${_output.style.path(plan.outputPath)}');
    _output.info('Repository: ${_output.style.url(plan.repositoryUrl)}');
    _output.info('SDK: ${plan.sdkVersion} (${plan.sdkLine})');
    _output.info('Branch: ${plan.branch}');
    _output.info('Template: ${plan.template}');
    _output.info('Platforms: ${plan.platforms}');
    if (plan.flutterCreateOrg != null) {
      _output.info('Flutter create org: ${plan.flutterCreateOrg}');
    }
    _output.next('Run without --plan after confirming these values');
    return 0;
  }

  Directory _destination(String repositoryName) {
    final output = argResults!.option('output')?.trim();
    if (output != null && output.isNotEmpty) {
      final directory = Directory(output);
      return directory.isAbsolute
          ? directory
          : Directory('${environment.workingDirectory.path}/$output');
    }
    return Directory('${environment.workingDirectory.path}/$repositoryName');
  }

  String _repositoryNameFromOptions(String packageName) {
    final name = argResults!.option('repository-name')?.trim() ?? packageName;
    if (name.isEmpty) {
      usageException('--repository-name must not be empty.');
    }
    if (name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      usageException(
        '--repository-name must be a repository name, not a path.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      usageException(
        '--repository-name may contain only letters, numbers, ".", "_", and "-".',
      );
    }
    return name;
  }

  String _platformsFromOptions() {
    final value = argResults!.option('platforms')?.trim() ?? 'ohos';
    if (value.isEmpty) {
      usageException('--platforms must not be empty.');
    }
    final platforms = value.split(',').map((platform) => platform.trim());
    final normalized = <String>[];
    final seen = <String>{};
    for (final platform in platforms) {
      if (platform.isEmpty) {
        usageException('--platforms must not contain empty entries.');
      }
      if (fluohPlatformFromCliName(platform) == null) {
        usageException(
          'Unsupported --platforms value "$platform". Supported values: '
          '${fluohPlatformCliNames.join(', ')}.',
        );
      }
      if (!seen.add(platform)) {
        usageException('Duplicate --platforms value "$platform".');
      }
      normalized.add(platform);
    }
    return normalized.join(',');
  }

  String? _flutterCreateOrgFromOptions() {
    final org = argResults!.option('org')?.trim();
    if (org == null) {
      return null;
    }
    if (org.isEmpty) {
      usageException('--org must not be empty.');
    }
    return org;
  }

  PackageGitAuthor? _gitAuthorConfigFromOptions() {
    final name = argResults!.option('git-author-name')?.trim();
    final email = argResults!.option('git-author-email')?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    if (!hasName && !hasEmail) {
      return null;
    }
    if (!hasName || !hasEmail) {
      usageException(
        'Pass both --git-author-name and --git-author-email, or omit both.',
      );
    }
    return PackageGitAuthor(name: name, email: email);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      'Name: Dart package name to create.',
      '',
      argParser.usage,
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

class _PackageNewPlan {
  const _PackageNewPlan({
    required this.packageName,
    required this.repositoryName,
    required this.repositoryUrl,
    required this.outputPath,
    required this.sdkVersion,
    required this.sdkLine,
    required this.branch,
    required this.template,
    required this.platforms,
    required this.flutterCreateOrg,
    required this.gitAuthor,
  });

  final String packageName;
  final String repositoryName;
  final String repositoryUrl;
  final String outputPath;
  final String sdkVersion;
  final String sdkLine;
  final String branch;
  final String template;
  final String platforms;
  final String? flutterCreateOrg;
  final PackageGitAuthor? gitAuthor;

  Map<String, Object?> toJson() {
    return {
      'supportKind': 'package',
      'origin': {'kind': packageOriginCreated},
      'repository': {
        'name': repositoryName,
        'url': repositoryUrl,
        'outputPath': outputPath,
        'branch': branch,
      },
      'sdk': {'version': sdkVersion, 'line': sdkLine},
      'package': {'name': packageName, 'path': '.', 'status': 'experimental'},
      'flutterCreate': {
        'template': template,
        'platforms': platforms,
        if (flutterCreateOrg != null) 'org': flutterCreateOrg,
      },
      'gitAuthor': gitAuthor == null
          ? null
          : {'name': gitAuthor!.name, 'email': gitAuthor!.email},
      'willRun': [
        'git init main',
        'configure origin remote',
        if (gitAuthor != null) 'configure local Git author',
        'commit fixed main README index',
        'checkout $branch',
        'flutter create --template=$template --platforms=$platforms <outputPath>',
        'write fluoh.yaml, FLUOH.md, and doc/fluoh/$packageName/spec.md',
        'stage generated files',
      ],
      'willNotRunWithoutSeparateApproval': [
        'fluoh package release',
        'git push',
        'git push --force',
        'pub.dev publish',
      ],
    };
  }
}
