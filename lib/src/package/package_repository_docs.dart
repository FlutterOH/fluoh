import 'dart:io';

import 'manifest/package_manifest.dart';

/// Package-specific values used when generating repository guidance documents.
class PackageRepositoryDocPackage {
  /// Creates a documentation package descriptor.
  const PackageRepositoryDocPackage({
    required this.name,
    required this.version,
    required this.packagePath,
    this.repositoryUrl,
  });

  /// Package name from the upstream pubspec.
  final String name;

  /// Upstream package version targeted by the adaptation.
  final String version;

  /// Package path inside the FlutterOH repository.
  final String packagePath;

  /// FlutterOH package repository URL, when known.
  final String? repositoryUrl;

  /// Recommended package verification command.
  String get verifyCommand =>
      packagePath == '.' ? 'fluoh verify' : 'fluoh verify --package $name';

  /// OHOS run command for default target selection.
  String get ohosRunCommand => packagePath == '.'
      ? 'fluoh run --platform ohos --json'
      : 'fluoh run --platform ohos --package $name --json';

  /// OHOS run command with an explicit connected device placeholder.
  String get ohosDeviceRunCommand => packagePath == '.'
      ? 'fluoh run --platform ohos --device <id> --json'
      : 'fluoh run --platform ohos --package $name --device <id> --json';

  /// OHOS build command used when no runnable target is available.
  String get ohosBuildCommand => packagePath == '.'
      ? 'fluoh build --platform ohos --auto-sign --json'
      : 'fluoh build --platform ohos --package $name --auto-sign --json';

  /// Android example run command.
  String get androidRunCommand => packagePath == '.'
      ? 'fluoh run --platform android --json'
      : 'fluoh run --platform android --package $name --json';

  /// Android emulator run command alias used by generated guidance.
  String get androidEmulatorRunCommand => androidRunCommand;

  /// iOS example run command.
  String get iosRunCommand => packagePath == '.'
      ? 'fluoh run --platform ios --json'
      : 'fluoh run --platform ios --package $name --json';

  /// iOS simulator run command alias used by generated guidance.
  String get iosSimulatorRunCommand => iosRunCommand;

  /// macOS example run command.
  String get macosRunCommand => packagePath == '.'
      ? 'fluoh run --platform macos --json'
      : 'fluoh run --platform macos --package $name --json';

  /// Command that completes the fluoh package release by creating the tag.
  String get releaseCommand => packagePath == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';

  /// Release gate command that validates without creating tags.
  String get releaseCheckCommand => packagePath == '.'
      ? 'fluoh package check'
      : 'fluoh package check --package $name';

  /// Command that updates package release version metadata.
  String get versionCommand => packagePath == '.'
      ? 'fluoh package version'
      : 'fluoh package version --package $name';

  /// Command that reports package release readiness.
  String get statusCommand => packagePath == '.'
      ? 'fluoh package status'
      : 'fluoh package status --package $name';

  /// Conventional example app path for this package.
  String get examplePath =>
      packagePath == '.' ? 'example' : '$packagePath/example';
}

/// Template version for generated `FLUOH.md` package guidance.
const int packageImplementationGuideTemplateVersion = 1;

/// Template version for generated `AGENTS.md` package guidance.
const int packageAgentsInstructionsTemplateVersion = 1;

/// Template version for generated root `README.md` package guidance.
const int packageReadmeAdaptationTemplateVersion = 1;

const String _reportCheckCommand =
    'python3 <skill-dir>/scripts/check_report.py <report-path>';

/// Builds documentation package descriptors from a package manifest.
List<PackageRepositoryDocPackage> packageRepositoryDocPackagesForManifest(
  PackageManifest manifest,
) {
  return [
    PackageRepositoryDocPackage(
      name: manifest.package.name,
      version: manifest.package.upstreamVersion,
      packagePath: manifest.package.path,
      repositoryUrl: manifest.repositoryUrl,
    ),
  ];
}

/// Writes or updates the generated root `README.md` adaptation section.
///
/// Package adaptation repositories describe one package per branch, so
/// [packages] must contain the current branch package only.
Future<void> writeOrReplacePackageReadmeAdaptation({
  required Directory destination,
  required List<PackageRepositoryDocPackage> packages,
}) async {
  final file = File('${destination.path}/README.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  await file.writeAsString(
    updatedPackageReadmeAdaptationContent(
      packages: packages,
      existing: existing,
    ),
  );
}

/// Returns root `README.md` content with package adaptation guidance refreshed.
///
/// Package adaptation repositories describe one package per branch, so
/// [packages] must contain the current branch package only.
String updatedPackageReadmeAdaptationContent({
  required List<PackageRepositoryDocPackage> packages,
  required String? existing,
}) {
  final generated = packageReadmeAdaptationContent(packages: packages);
  return _contentWithReadmeGeneratedSection(
    existing,
    generated,
    sectionId: _readmeAdaptationSectionId,
    templateVersion: packageReadmeAdaptationTemplateVersion,
    fallbackTitle: packages.single.name,
  );
}

/// Builds generated root `README.md` package adaptation guidance.
///
/// Package adaptation repositories describe one package per branch, so
/// [packages] must contain the current branch package only.
String packageReadmeAdaptationContent({
  required List<PackageRepositoryDocPackage> packages,
}) {
  final package = packages.single;
  final badge = _latestReleaseBadgeMarkdown(package);
  final lines = <String>[
    '## FlutterOH adaptation',
    '',
    ?badge,
    if (badge != null) '',
    'This branch maintains the FlutterOH adaptation for this package. The original README continues below.',
    '',
    '- Metadata: [fluoh.yaml](fluoh.yaml)',
    '- Maintainer guide: [FLUOH.md](FLUOH.md)',
    '- Release notes: [FLUOH_CHANGELOG.md](FLUOH_CHANGELOG.md)',
  ];
  if (package.packagePath != '.') {
    lines.add(
      '- Package path: [${package.packagePath}](${package.packagePath})',
    );
  }
  lines.add('- Validation: `${package.releaseCheckCommand}`');
  lines.add('');
  return lines.join('\n');
}

String? _latestReleaseBadgeMarkdown(PackageRepositoryDocPackage package) {
  final githubRepository = _githubRepositoryPath(package.repositoryUrl);
  if (githubRepository == null) {
    return null;
  }
  final badgeUrl =
      'https://img.shields.io/github/v/tag/$githubRepository'
      '?label=release&sort=date&filter=${package.name}-*';
  final tagsUrl = 'https://github.com/$githubRepository/tags';
  return '[![Latest release]($badgeUrl)]($tagsUrl)';
}

String? _githubRepositoryPath(String? repositoryUrl) {
  final value = repositoryUrl?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }

  final scpLike = RegExp(
    r'^(?:git@)?github\.com:([^/]+)/(.+)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (scpLike != null) {
    return _normalizedGithubRepositoryPath(
      owner: scpLike.group(1)!,
      repository: scpLike.group(2)!,
    );
  }

  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.toLowerCase() != 'github.com') {
    return null;
  }
  final segments = uri.pathSegments
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (segments.length < 2) {
    return null;
  }
  return _normalizedGithubRepositoryPath(
    owner: segments[0],
    repository: segments[1],
  );
}

String? _normalizedGithubRepositoryPath({
  required String owner,
  required String repository,
}) {
  final normalizedOwner = owner.trim();
  final normalizedRepository = repository
      .trim()
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'\.git$', caseSensitive: false), '');
  if (normalizedOwner.isEmpty || normalizedRepository.isEmpty) {
    return null;
  }
  return '$normalizedOwner/$normalizedRepository';
}

/// Writes or updates the generated `FLUOH.md` implementation guide section.
Future<void> writeOrReplacePackageImplementationGuide({
  required Directory destination,
  required List<PackageRepositoryDocPackage> packages,
}) async {
  final file = File('${destination.path}/FLUOH.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  await file.writeAsString(
    updatedPackageImplementationGuideContent(
      packages: packages,
      existing: existing,
    ),
  );
}

/// Returns `FLUOH.md` content with the generated implementation guide refreshed.
String updatedPackageImplementationGuideContent({
  required List<PackageRepositoryDocPackage> packages,
  required String? existing,
}) {
  final generated = packageImplementationGuideContent(
    packages: packages,
    includeTitle: true,
  );
  return _contentWithGeneratedSection(
    existing,
    generated,
    sectionId: _implementationGuideSectionId,
    templateVersion: packageImplementationGuideTemplateVersion,
  );
}

/// Writes or updates the generated package instructions in `AGENTS.md`.
Future<void> writeOrReplacePackageAgentsInstructions({
  required Directory destination,
  required List<PackageRepositoryDocPackage> packages,
}) async {
  final file = File('${destination.path}/AGENTS.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  await file.writeAsString(
    updatedPackageAgentsInstructionsContent(
      packages: packages,
      existing: existing,
    ),
  );
}

/// Returns `AGENTS.md` content with the generated package instructions refreshed.
String updatedPackageAgentsInstructionsContent({
  required List<PackageRepositoryDocPackage> packages,
  required String? existing,
}) {
  final generated = packageAgentsInstructionsContent(
    packages: packages,
    includeTitle: _generatedSectionOwnsFile(
      existing,
      sectionId: _agentsInstructionsSectionId,
    ),
  );
  return _contentWithGeneratedSection(
    existing,
    generated,
    sectionId: _agentsInstructionsSectionId,
    templateVersion: packageAgentsInstructionsTemplateVersion,
  );
}

/// Builds generated `AGENTS.md` guidance for one or more package entries.
String packageAgentsInstructionsContent({
  required List<PackageRepositoryDocPackage> packages,
  required bool includeTitle,
}) {
  final packageLine = packages.length == 1
      ? '- Current package: `${packages.single.name}`.'
      : '- Current packages: ${packages.map((package) => '`${package.name}`').join(', ')}.';
  return [
    if (includeTitle) '# AGENTS.md',
    if (includeTitle) '',
    '## FlutterOH/OHOS Adaptation',
    '',
    'For FlutterOH/OHOS package adaptation tasks, follow `FLUOH.md`.',
    '',
    'Keep the existing instructions in this `AGENTS.md` as the primary repository rules. Use `FLUOH.md` only for fluoh package workflow, verification, release evidence, and handoff requirements.',
    packageLine,
    '',
  ].join('\n');
}

List<String> _localCommitCheckpointLines({
  required bool multiPackage,
  String? packageScope,
}) {
  final packageCommitScope = packageScope ?? '<name>';
  final commitScopeGuidance = multiPackage
      ? '- Use Conventional Commits with the package name as the scope for package-specific changes, such as `feat($packageCommitScope): add OHOS platform scaffold` or `test($packageCommitScope): cover OHOS channel calls`. Use repository-level scopes such as `docs`, `ci`, or `release` only for changes that are not specific to one package.'
      : '- Use Conventional Commits without a package-name scope when the current branch adapts only this package, such as `feat: add OHOS platform scaffold` or `test: cover OHOS channel calls`. Use a scope only when it adds real context, such as `docs`, `ci`, `example`, or `release`.';
  return [
    '## Local Commit Checkpoints',
    '',
    '- Before adaptation commits, resolve the repository URL/path recorded in `repository.git.url` and the local Git author identity that will be used for commits.',
    '- Create small local commits at completed checkpoints instead of one large final commit when the workflow needs commits, such as before package sync, package check, or handoff. Before each commit, self-review the staged paths, commit message, and local Git author identity.',
    '- Keep commits local unless the maintainer explicitly asks you to push.',
    '- Before the first commit, run `git config --local --get user.name` and `git config --local --get user.email`; if either is missing or contradicts the resolved identity, ask for author info, then set `git config --local user.name <name>` and `git config --local user.email <email>`. New package repositories can also be created with `fluoh package create <upstream> --repository-name <repository-name> --git-author-name <name> --git-author-email <email>`.',
    '- Stage explicit paths for each checkpoint and review `git diff --cached` before committing.',
    '- Commit generated baseline files separately before implementation changes when `fluoh package create` or `fluoh package add` creates a package branch.',
    '- Suggested checkpoints: generated baseline, selected-SDK baseline fixes, OHOS scaffold, each implemented feature, tests and example verification, then release metadata.',
    '- Commit only after the checkpoint\'s relevant command succeeds; note skipped device-only checks in the commit body.',
    commitScopeGuidance,
    '- Do not commit failing work unless the maintainer explicitly requests a local WIP checkpoint.',
    '',
  ];
}

List<String> _adaptationGuardrailLines() {
  return [
    '## Guardrails',
    '',
    '- Ask before changing Dart public APIs, package names, dependency constraints, non-default release version policy, manual release version overrides, repository remotes, or branch layout. Normal package version/status metadata updates in this workflow do not need separate confirmation.',
    '- Ask before deleting upstream files, replacing platform implementations wholesale, force-pushing, running destructive Git commands, or committing failing work.',
    '- Do not invent OHOS APIs, permissions, manifest fields, or signing values. Derive them from upstream platform behavior, generated errors, or existing FlutterOH package implementations; stop and ask when the source is unclear.',
    '- Preserve the local worktree on network, GitHub, push, sync, or release failures; summarize the failure and leave retryable next steps.',
    '',
  ];
}

List<String> _multiAdaptationCommandFlowLines() {
  return [
    '## Automatic Adaptation Command Flow',
    '',
    'Use this command flow as the primary loop. The detailed workflow and platform matrix below add context, but these commands decide when to edit, when to fix local environment, and when the work can be handed back.',
    '',
    '1. Repository setup: use `fluoh package create <upstream> --repository-name <repository-name>` to create the first package branch, `fluoh package add <package-path>` to create another package branch from that package release, and `fluoh package sync` only after a completed, committed checkpoint when an upstream package release needs to be merged. Omitted upstream targets resolve to the latest valid package release tag; use `--upstream-version <version>` only when adapting a specific same-or-newer upstream version. `fluoh package sync` refuses upstream downgrades; mark the current adaptation `broken` with `fluoh package version --status broken` instead. For whole-repository work, build a package queue and finish one package branch checkpoint sequence before moving to the next package.',
    '2. Baseline gates: run `fluoh deps get`, `fluoh doctor --project --json --strict`, `fluoh flutter analyze`, and existing package or example tests before adding OHOS code. Project warnings mean repository fixes; environment warnings mean local toolchain or Source fixes.',
    '3. Implementation loop: after code, dependency, SDK, or metadata changes, rerun `fluoh deps get` when needed, then `fluoh verify --package <name> --json` until pub get, analysis, and existing tests pass.',
    '4. OHOS loop: run `fluoh run --platform ohos --package <name> --json`, or add `--device <id>` for a connected hdc target. This proves build, signing, install, launch, and hilog diagnostics; then complete required example functional interactions with AI-assisted automation when possible and record evidence. If no target is available, run `fluoh build --platform ohos --package <name> --auto-sign --json` as build-only evidence and record the blocker.',
    '5. Existing-platform loop: for Android, run `fluoh doctor --platform android --json --strict`, then `fluoh run --platform android --package <name> --json` when `example/android` exists. For iOS, run `fluoh doctor --platform ios --json --strict`, then `fluoh run --platform ios --package <name> --json` when `example/ios` exists. For macOS, run `fluoh doctor --platform macos --json --strict`, then `fluoh run --platform macos --package <name> --json` when `example/macos` exists. Add or run `integration_test/` for tappable workflows; otherwise run an AI-assisted interaction scenario and record evidence.',
    '6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`, `stderrTail`, and saved logs before editing. Fix `doctor` failures in local tooling, project warnings in repository configuration, and verification failures in the package or example that produced the diagnostic.',
    '7. Implementation checkpoint: once implementation, OHOS evidence, and applicable existing-platform regression checks are clean or explicitly blocked, create a local implementation checkpoint commit. This clean worktree is required before `fluoh package version`, `fluoh package sync`, and `fluoh package check`.',
    '8. Release metadata checkpoint: run `fluoh package status --package <name>`, update release metadata with `fluoh package version --package <name>` when needed, update `FLUOH_CHANGELOG.md`, review `fluoh.yaml`, then create a local release metadata checkpoint commit. `fluoh package version` requires a clean worktree before it writes metadata.',
    '9. Final report and release gate: rerun final `fluoh verify --package <name>`, create `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md` with command results, platform matrix, interaction evidence, signing mode, logs, risks, and release recommendation, run `$_reportCheckCommand`, then run `fluoh package check --package <name> --report .fluoh/ai-report-<name>-YYYYMMDD-HHMMSS.md`. `.fluoh/` is ignored local state and must not be committed, so the worktree should remain clean for package check. Add `--require-ohos-run` when an OHOS target was available and the handoff must prove a passed real run. Maintainers can still use baseline `fluoh package check --package <name>` after their own manual verification. Release only after maintainer approval with `fluoh package release --package <name>`.',
    '',
  ];
}

List<String> _singleAdaptationCommandFlowLines(
  PackageRepositoryDocPackage package,
) {
  return [
    '## Automatic Adaptation Command Flow',
    '',
    'Use this command flow as the primary loop. The detailed workflow and platform matrix below add context, but these commands decide when to edit, when to fix local environment, and when the work can be handed back.',
    '',
    '1. Repository setup: use `fluoh package create <upstream> --repository-name <repository-name>` for a new repository and `fluoh package sync` only after a completed, committed checkpoint when an upstream package release needs to be merged. Omitted upstream targets resolve to the latest valid package release tag; use `--upstream-version <version>` only when adapting a specific same-or-newer upstream version. `fluoh package sync` refuses upstream downgrades; mark the current adaptation `broken` with `fluoh package version --status broken` instead.',
    '2. Baseline gates: run `fluoh deps get`, `fluoh doctor --project --json --strict`, `fluoh flutter analyze`, and existing package or example tests before adding OHOS code. Project warnings mean repository fixes; environment warnings mean local toolchain or Source fixes.',
    '3. Implementation loop: after code, dependency, SDK, or metadata changes, rerun `fluoh deps get` when needed, then `${package.verifyCommand} --json` until pub get, analysis, and existing tests pass.',
    '4. OHOS loop: run `${package.ohosRunCommand}`, or `${package.ohosDeviceRunCommand}` for a connected hdc target. This proves build, signing, install, launch, and hilog diagnostics; then complete required example functional interactions with AI-assisted automation when possible and record evidence. If no target is available, run `${package.ohosBuildCommand}` as build-only evidence and record the blocker.',
    '5. Existing-platform loop: for Android, run `fluoh doctor --platform android --json --strict`, then `${package.androidEmulatorRunCommand}` when `${package.examplePath}/android` exists. For iOS, run `fluoh doctor --platform ios --json --strict`, then `${package.iosSimulatorRunCommand}` when `${package.examplePath}/ios` exists. For macOS, run `fluoh doctor --platform macos --json --strict`, then `${package.macosRunCommand}` when `${package.examplePath}/macos` exists. Add or run `${package.examplePath}/integration_test/` for tappable workflows; otherwise run an AI-assisted interaction scenario and record evidence.',
    '6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`, `stderrTail`, and saved logs before editing. Fix `doctor` failures in local tooling, project warnings in repository configuration, and verification failures in the package or example that produced the diagnostic.',
    '7. Implementation checkpoint: once implementation, OHOS evidence, and applicable existing-platform regression checks are clean or explicitly blocked, create a local implementation checkpoint commit. This clean worktree is required before `${package.versionCommand}`, `fluoh package sync`, and `${package.releaseCheckCommand}`.',
    '8. Release metadata checkpoint: run `${package.statusCommand}`, update release metadata with `${package.versionCommand}` when needed, update `FLUOH_CHANGELOG.md`, review `fluoh.yaml`, then create a local release metadata checkpoint commit. `${package.versionCommand}` requires a clean worktree before it writes metadata.',
    '9. Final report and release gate: rerun final `${package.verifyCommand}`, create `.fluoh/ai-report-${package.name}-YYYYMMDD-HHMMSS.md` with command results, platform matrix, interaction evidence, signing mode, logs, risks, and release recommendation, run `$_reportCheckCommand`, then run `${package.releaseCheckCommand} --report .fluoh/ai-report-${package.name}-YYYYMMDD-HHMMSS.md`. `.fluoh/` is ignored local state and must not be committed, so the worktree should remain clean for package check. Add `--require-ohos-run` when an OHOS target was available and the handoff must prove a passed real run. Maintainers can still use baseline `${package.releaseCheckCommand}` after their own manual verification. Release only after maintainer approval with `${package.releaseCommand}`.',
    '',
  ];
}

List<String> _multiPlatformVerificationLines() {
  return [
    '## Platform Verification Matrix',
    '',
    '- OHOS: run `fluoh run --platform ohos --package <name> --json`, or add `--device <id>` for a connected hdc target. This is the authoritative OHOS build, signing, install, launch, hilog, and diagnostics loop.',
    '- Android: when `example/android` exists, first run `fluoh doctor --platform android --json --strict`, then run `fluoh run --platform android --package <name> --json` or add `--device <id>` for an already connected target. If `integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- iOS: when `example/ios` exists, first run `fluoh doctor --platform ios --json --strict`, then run `fluoh run --platform ios --package <name> --json` on a simulator or add `--device <id>` for an already connected target. If `integration_test/` exists, the command runs it on the selected target after the smoke run. Do not commit team-specific signing state.',
    '- macOS: when `example/macos` exists, first run `fluoh doctor --platform macos --json --strict`, then run `fluoh run --platform macos --package <name> --json` on the local host. If `integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- For Android/iOS/macOS run smoke checks, `fluoh run` launches the app, waits for Flutter launch output, captures output for `--log-duration`, captures `details.vmServiceUri` when Flutter prints a VM Service or debug service URI, optionally writes a live `flutterRunSession` file with `--session-file <path>` while the app is still running, sends `q`, saves the output under `\$FLUOH_HOME/cache/package-runs`, and reports runtime failures through JSON diagnostics. AI agents can run `python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>` to wait for launch, find the VM Service URI, attach through debug tooling, or route a failure without screenshot recognition.',
    '- Run smoke is not enough for workflows that need UI taps, permission prompts, files, camera, location, media playback, deep links, or external apps. Cover those flows with `integration_test/` where the platform runner supports it, or run an AI-assisted functional scenario and record exact steps, expected result, actual result, device or simulator id, Flutter debug/widget/semantic/log evidence, and optional screenshots.',
    '- Store scenario notes under `.fluoh/scenarios/<package>-<platform>-<name>.md` when the interaction is not already encoded as `integration_test`. The AI driver follows the scenario, operates the target with available device or UI tools, and records pass/fail evidence in the report. The scenario must be usable without screenshot recognition or UI appearance judgment by relying on Flutter debug or VM service output, widget/component tree state, semantics, stable text, command JSON, or logs.',
    '- Consider every applicable interaction class before release: permission grant and denial, file or media picker, camera or microphone capture, location and sensors, maps, media playback or recording, deep links and external app callbacks, background or lifecycle behavior, multi-step forms, and negative/error paths. If none apply, write `No interaction required: <reason>` in the report.',
    '- OHOS `fluoh run` does not currently automate page traversal or button taps. After a successful OHOS launch, use AI-assisted interaction on the emulator or device for required example flows unless another automation has already done so.',
    '- Release recommendation `ready` requires passing build and run or integration evidence for every existing supported platform directory. A missing local Android, Xcode, macOS host, device, or simulator environment is a maintainer-decision blocker, not a ready release.',
    '- Record each platform as `not present`, `passed`, `failed`, or `skipped with blocker` in the `.fluoh/ai-report-...md` platform matrix. Include command, device id or simulator id, exit result, and relevant output tail.',
    '',
  ];
}

List<String> _singlePlatformVerificationLines(
  PackageRepositoryDocPackage package,
) {
  return [
    '## Platform Verification Matrix',
    '',
    '- OHOS: run `${package.ohosRunCommand}`, or `${package.ohosDeviceRunCommand}` for a connected hdc target. This is the authoritative OHOS build, signing, install, launch, hilog, and diagnostics loop.',
    '- Android: when `${package.examplePath}/android` exists, first run `fluoh doctor --platform android --json --strict`, then run `${package.androidEmulatorRunCommand}` or `${package.androidRunCommand} --device <id>` for an already connected target. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- iOS: when `${package.examplePath}/ios` exists, first run `fluoh doctor --platform ios --json --strict`, then run `${package.iosSimulatorRunCommand}` on a simulator or `${package.iosRunCommand} --device <id>` for an already connected target. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run. Do not commit team-specific signing state.',
    '- macOS: when `${package.examplePath}/macos` exists, first run `fluoh doctor --platform macos --json --strict`, then run `${package.macosRunCommand}` on the local host. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- For Android/iOS/macOS run smoke checks, `fluoh run` launches the app, waits for Flutter launch output, captures output for `--log-duration`, captures `details.vmServiceUri` when Flutter prints a VM Service or debug service URI, optionally writes a live `flutterRunSession` file with `--session-file <path>` while the app is still running, sends `q`, saves the output under `\$FLUOH_HOME/cache/package-runs`, and reports runtime failures through JSON diagnostics. AI agents can run `python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>` to wait for launch, find the VM Service URI, attach through debug tooling, or route a failure without screenshot recognition.',
    '- Run smoke is not enough for workflows that need UI taps, permission prompts, files, camera, location, media playback, deep links, or external apps. Cover those flows with `${package.examplePath}/integration_test/` where the platform runner supports it, or run an AI-assisted functional scenario and record exact steps, expected result, actual result, device or simulator id, Flutter debug/widget/semantic/log evidence, and optional screenshots.',
    '- Store scenario notes under `.fluoh/scenarios/${package.name}-<platform>-<name>.md` when the interaction is not already encoded as `integration_test`. The AI driver follows the scenario, operates the target with available device or UI tools, and records pass/fail evidence in the report. The scenario must be usable without screenshot recognition or UI appearance judgment by relying on Flutter debug or VM service output, widget/component tree state, semantics, stable text, command JSON, or logs.',
    '- Consider every applicable interaction class before release: permission grant and denial, file or media picker, camera or microphone capture, location and sensors, maps, media playback or recording, deep links and external app callbacks, background or lifecycle behavior, multi-step forms, and negative/error paths. If none apply, write `No interaction required: <reason>` in the report.',
    '- OHOS `${package.ohosRunCommand}` does not currently automate page traversal or button taps. After a successful OHOS launch, use AI-assisted interaction on the emulator or device for required example flows unless another automation has already done so.',
    '- Release recommendation `ready` requires passing build and run or integration evidence for every existing supported platform directory. A missing local Android, Xcode, macOS host, device, or simulator environment is a maintainer-decision blocker, not a ready release.',
    '- Record each platform as `not present`, `passed`, `failed`, or `skipped with blocker` in the `.fluoh/ai-report-${package.name}-...md` platform matrix. Include command, device id or simulator id, exit result, and relevant output tail.',
    '',
  ];
}

List<String> _diagnosticsRoutingLines() {
  return [
    '## Diagnostics Routing',
    '',
    'When `fluoh run --platform <platform> --json` fails, read the failed package or step `nextCommand`, `stdoutTail`/`stderrTail`, and route by `diagnostics[].code` before editing:',
    '',
    '- `dart.pub_get_failed`: fix dependency declarations, SDK constraints, or local path overrides.',
    '- `dart.analysis_failed`: fix Dart code or generated bindings until analysis passes.',
    '- `dart.test_failed`: fix package or example behavior, then rerun tests.',
    '- `ohos.hap_build_failed`: fix OHOS project config, ArkTS, permissions, `reason`, `usedScene`, resources, or FlutterOH build errors.',
    '- `android.apk_build_failed`: fix Android project config, Gradle/Kotlin/Java code, shared Dart changes, or dependency regressions.',
    '- `ios.build_failed`: fix iOS project config, Swift/Objective-C code, shared Dart changes, dependency regressions, or document a local Xcode/toolchain blocker. The iOS build uses `--no-codesign`.',
    '- `macos.build_failed`: fix macOS project config, Swift/Objective-C code, shared Dart changes, dependency regressions, or document a local macOS/Xcode blocker.',
    '- `android.devices_failed`, `android.emulators_failed`, `ios.devices_failed`, `ios.emulators_failed`, `macos.devices_failed`: run `fluoh doctor --platform android --json --strict`, `fluoh doctor --platform ios --json --strict`, or `fluoh doctor --platform macos --json --strict` and fix native target tooling before editing package logic.',
    '- `android.device_missing`, `ios.device_missing`, `macos.device_missing`: connect a matching target or rerun the platform run command so fluoh can start a local emulator/simulator where available.',
    '- `android.device_not_found`, `ios.device_not_found`, `macos.device_not_found`: use an actual id from failed diagnostics or `fluoh devices --platform <platform>`.',
    '- `android.device_ambiguous`, `ios.device_ambiguous`, `macos.device_ambiguous`: pick one target and rerun with `--device <id>`.',
    '- `android.emulator_missing`, `ios.emulator_missing`, `macos.emulator_missing`: create a local Android emulator or iOS simulator before rerunning the platform run command; macOS has no emulator, so use the local host target.',
    '- `android.emulator_not_found`, `ios.emulator_not_found`, `macos.emulator_not_found`: choose an emulator from diagnostics and rerun with `--emulator <name>`; macOS should be rerun without `--emulator`.',
    '- `android.emulator_ambiguous`, `ios.emulator_ambiguous`, `macos.emulator_ambiguous`: pick one emulator from diagnostics and rerun with `--emulator <name>`.',
    '- `android.emulator_start_failed`, `ios.emulator_start_failed`, `macos.emulator_start_failed`: inspect native emulator launch output from `fluoh run` and repair the local emulator/simulator, or rerun macOS on the local host without `--emulator`.',
    '- `android.launch_timeout`, `ios.launch_timeout`, `macos.launch_timeout`: inspect run output, increase `--device-timeout` if the first launch is slow, or fix startup hangs.',
    '- `android.run_failed`, `ios.run_failed`, `macos.run_failed`: inspect `stdoutTail`/`stderrTail`, fix install, launch, dependency, or runtime startup failures.',
    '- `android.runtime_crash`, `ios.runtime_crash`, `macos.runtime_crash`: inspect the saved `outputLog` and fix the app crash or platform-channel failure.',
    '- `android.integration_test_failed`, `ios.integration_test_failed`, `macos.integration_test_failed`: fix integration test failures or the exercised example behavior.',
    '- `ohos.toolchain_missing`: install the OpenHarmony SDK toolchain with DevEco Studio or set `FLUOH_DEVECO_STUDIO`; do not edit package code for this.',
    '- `ohos.ohos_project_missing`: create or repair the example `ohos/` platform before signing or running.',
    '- `ohos.auto_sign_failed`: inspect the signing diagnostic and fix the project metadata or local toolchain before editing package logic.',
    '- `ohos.signing_profile_failed`: fix generated debug profile inputs, permissions, or local signing tools.',
    '- `ohos.build_profile_patch_failed`: fix `example/ohos/build-profile.json5` shape so temporary signing can be applied.',
    '- `ohos.direct_sign_failed`: inspect the HAP signing output and fix signing material or generated unsigned HAP state.',
    '- `ohos.launch_info_missing`: fix `AppScope/app.json5` or `module.json5` so the example has a bundle and launchable ability.',
    '- `ohos.hdc_targets_failed`: fix hdc or emulator environment; inspect hdc output before editing package code.',
    '- `ohos.emulator_start_failed`: create or repair a local OpenHarmony emulator, or rerun with `--device <id>`.',
    '- `ohos.device_missing`: start an OpenHarmony emulator or connect a device, then rerun the OHOS run command or add `--device <id>`.',
    '- `ohos.device_not_found`: use an actual id from `hdc list targets`.',
    '- `ohos.device_ambiguous`: pick one target and rerun with `--device <id>`.',
    '- `ohos.no_installable_hap`: ensure the HAP build produced a signed or directly signable output.',
    '- `ohos.install_failed`: inspect install stdout/stderr; fix signing, bundle conflicts, SDK mismatch, or device state.',
    '- `ohos.launch_failed`: fix bundle name, ability name, module metadata, permissions, or startup crash.',
    '- `ohos.runtime_crash`: open the hilog file from `details.hilog` or the step `reason`, fix the crash, and rerun.',
    '- `command.failed`: read the command, stdout, and stderr, then classify the failure manually.',
    '- Do not create a broad "all permissions" signature. Let `--auto-sign` regenerate the debug signing profile from the example\'s current permission declarations.',
    '',
    'Dependency status routing (from `fluoh deps check --json` and `fluoh deps fix --json`):',
    '',
    '- `unknown`: no OHOS implementation exists. Report in the completion report under "Unavailable"; do not attempt to implement the dependency yourself unless the maintainer asks.',
    '- `blocked`: source index marks this package as blocked for OHOS. Report in the completion report; note the block reason for the maintainer.',
    '- `sdk-mismatch`: OHOS implementations exist for other SDK lines but not the selected one. Report available SDK lines in the completion report; suggest switching SDK version or ask the maintainer.',
    '- `incompatible-version`: locked version has no exact or compatible implementation. Report in the completion report; suggest setting `dependencyPolicy.versionChanges` to `any` in `fluoh.yaml` if the maintainer accepts breaking changes.',
    '',
    'Sync and merge routing (from `fluoh package sync --json`):',
    '',
    '- `sync.merge_conflict`: upstream target merge produced file conflicts. For `fluoh.yaml` metadata conflicts, accept the upstream version and re-apply local package metadata. For OHOS platform files (`ohos/`, platform channels), preserve local OHOS implementations and manually integrate upstream changes. For non-OHOS files, accept upstream, including the target package pubspec version. Run `fluoh package sync --continue` after staging resolved files; if the interrupted sync used a non-tag `--upstream-ref`, pass the same ref again with `--continue`.',
    '- `sync.merge_failed`: git could not merge the upstream target and did not leave resolvable file conflicts. Inspect `stderrTail`, fix the branch or repository state, then retry `fluoh package sync --json`.',
    '- `sync.fetch_failed`: upstream fetch failed, likely a network issue. Verify network access to the upstream repository, then retry.',
    '',
  ];
}

List<String> _completionReportLines() {
  return [
    '## Completion Report',
    '',
    '- Before final response, create a timestamped report in the repository root using `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md`. Use local time, 24-hour time, and a timestamp precise to seconds, for example `.fluoh/ai-report-camera-20260526-153045.md`. Create `.fluoh/` if needed; it is local state and must not be committed.',
    '- The report must include: package name, upstream version, FlutterOH SDK version, implementation summary, changed files, public API changes if any, permissions and OHOS config changes, commands run with exit results and relevant output tails, final `fluoh run --platform <platform> --json` outcome, a platform matrix for OHOS/Android/iOS/macOS with build, run, integration-test, device/simulator, and skip-blocker fields, functional interaction evidence for required scenarios, signing mode, generated HAP paths, hilog path when present, remaining risks, and release recommendation.',
    '- End the report with one of: `Release recommendation: ready`, `Release recommendation: needs maintainer decision`, or `Release recommendation: blocked`, followed by the exact reason.',
    '- If the maintainer asks for another iteration, create a new timestamped report for that completed iteration so earlier reports remain available.',
    '',
  ];
}

/// Builds generated `FLUOH.md` implementation guidance.
String packageImplementationGuideContent({
  required List<PackageRepositoryDocPackage> packages,
  required bool includeTitle,
}) {
  if (packages.length == 1) {
    return _singlePackageImplementationGuideContent(
      package: packages.single,
      includeTitle: includeTitle,
    );
  }

  return [
    if (includeTitle) '# FlutterOH Implementation',
    if (includeTitle) '',
    'This repository is being used for a package-branch adaptation queue. Current SDK, package path, upstream version, release version, and release status are recorded in the current branch `fluoh.yaml`.',
    '',
    '## Packages',
    '',
    for (final package in packages)
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, example `${package.examplePath}`, verify command `${package.verifyCommand}`, version command `${package.versionCommand}`, release check `${package.releaseCheckCommand}`, release command `${package.releaseCommand}`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the current upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package metadata: `package` in the current branch `fluoh.yaml`',
    '- Repository URL/path: `repository.git.url` in `fluoh.yaml`',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '- Command help: `fluoh help`, `fluoh help package`, and `fluoh help verify`',
    '',
    '## Adaptation Checklist',
    '',
    '- For each package, confirm the Dart API surface, existing platform implementations, platform-channel or native entry points, permissions, configuration files, example flows, automated tests, and device-only checks before editing.',
    for (final package in packages)
      '- `${package.name}`: inspect `${package.packagePath}`, `${package.examplePath}`, package tests, example tests, and pubspec constraints.',
    '- Keep assumptions close to the current diff; remove stale notes before release.',
    '',
    ..._adaptationGuardrailLines(),
    ..._multiAdaptationCommandFlowLines(),
    ..._multiPlatformVerificationLines(),
    ..._diagnosticsRoutingLines(),
    '## Next Steps',
    '',
    '1. Establish a selected-SDK and native-platform baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds. Include the matching Android/iOS/macOS run command when the example has that platform directory and the local toolchain is available, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for the current package branch.',
    '3. Use upstream package tests and existing example tests as the automated baseline before calling the package complete.',
    '4. Keep package tests and example tests deterministic, with existing example apps for AI-assisted or manual platform verification.',
    '5. Run the full automated OHOS loop for each package example when a local OpenHarmony emulator or device is available: `fluoh run --platform ohos --package <name> --json`. Add `--device <id>` for an already connected hdc target. Use `fluoh build --platform ohos --package <name> --auto-sign --json` as a build-only fallback when no device is available. JSON `nextCommand` and `diagnostics` give the next failure category. Complete and record required OHOS example functional interactions separately because the run command does not click through pages.',
    '6. Run Android, iOS, and macOS regression checks after shared or example changes when their platform directories exist: run `fluoh doctor --project --json --strict`, then use `fluoh run --platform android --package <name> --json` for Android, `fluoh run --platform ios --package <name> --json` for iOS, and `fluoh run --platform macos --package <name> --json` for macOS, or add `--device <id>` for already connected targets. iOS builds use `--no-codesign`; document unavailable local Android/Xcode/macOS host toolchains instead of guessing. Add `integration_test/` or AI-assisted interaction evidence for flows beyond launch smoke.',
    '7. Run `fluoh doctor --project --json --strict` when local native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot state is unclear.',
    '8. Commit the implementation checkpoint before release metadata commands; `fluoh package version --package <name>` requires a clean worktree before it writes metadata.',
    '9. Use `fluoh package version --package <name>` and update `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change, then commit the release metadata checkpoint.',
    '10. Run final `fluoh verify --package <name>`, create the ignored `.fluoh/ai-report-...md`, run `$_reportCheckCommand`, then run `fluoh package check --package <name> --report <report-path>` while the tracked worktree is clean.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml` to confirm SDK version, package path, upstream version, current release status, and example location.',
    '2. Baseline: for each package, run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds with the selected SDK before changing OHOS code. Include Android/iOS/macOS run commands when `example/android`, `example/ios`, or `example/macos` exists and local toolchains are available; fix non-OHOS regressions first.',
    '3. Plan: inspect the upstream Dart API and platform implementations, then identify required OHOS entry points, permissions, config files, tests, example flows, and device checks.',
    '4. Implement: add OHOS code without changing upstream public APIs unless upstream requires it.',
    '5. Test: add deterministic automated checks to existing package tests and example tests. Cover arguments, return shape, errors, and platform-channel names when applicable.',
    '6. Example: from each existing package example, run `fluoh sdk use <sdk-version> --pub-get` when the IDE link is missing or stale. Extend examples from their existing platforms plus OHOS, including operation, expected result, pass/fail status, and failure hint.',
    '7. Build and run OHOS: use `fluoh run --platform ohos --package <name> --json` to build, auto-sign, install, launch, capture hilog, and classify failures. Then perform required example functional interactions on the emulator or device and record evidence. Fix permission, `reason`, `usedScene`, ArkTS, install, launch, runtime, or interaction diagnostics before release.',
    '8. Check existing platforms: follow the Platform Verification Matrix. Run `fluoh run --platform android --package <name> --json` when an Android example exists, `fluoh run --platform ios --package <name> --json` when an iOS example exists, and `fluoh run --platform macos --package <name> --json` when a macOS example exists, or add `--device <id>` for already connected targets. Use `integration_test/` or AI-assisted interaction evidence for scenario coverage beyond launch smoke. Record exact skip reasons for unavailable local toolchains.',
    '9. Release prep: keep `package.release.status: experimental` until that package is implemented, tested, and ready to be recommended. Run `fluoh deps get` after dependency or metadata changes, run the matching `fluoh verify --package <name>`, then commit the implementation checkpoint.',
    '10. Finish: update release metadata, update `FLUOH_CHANGELOG.md`, commit the release metadata checkpoint, run final `fluoh verify --package <name>`, create the ignored `.fluoh/ai-report-...md`, run `$_reportCheckCommand`, then run `fluoh package check --package <name> --report <report-path>`. Use `fluoh package release --package <name>` only after maintainer approval.',
    '',
    '## Release Readiness',
    '',
    '- Public Dart APIs remain compatible with upstream unless upstream changed them.',
    '- Automated package and example tests cover the adapted behavior where practical.',
    '- Device-only behavior and UI interaction flows have an automated `integration_test`, AI-assisted interaction evidence, an explicitly accepted manual result, or a clear remaining blocker.',
    '- The full OHOS run succeeds when a local emulator or device is available; otherwise the device-only blocker is documented.',
    '- Android, iOS, and macOS example builds, run smoke checks, and integration tests pass when those platforms exist and local toolchains are available; unavailable toolchains are documented with exact skipped commands and block a `ready` recommendation.',
    '- `FLUOH_CHANGELOG.md`, `fluoh.yaml`, package status, and release version are ready for `fluoh package check` and `fluoh package release`.',
    '',
    ..._completionReportLines(),
    ..._localCommitCheckpointLines(multiPackage: true),
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

String _singlePackageImplementationGuideContent({
  required PackageRepositoryDocPackage package,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# FlutterOH Implementation',
    if (includeTitle) '',
    'This repository contains the OHOS implementation for `${package.name}`. Current SDK, package path, upstream version, release version, and release status are recorded in `fluoh.yaml`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package metadata: `package` in `fluoh.yaml`',
    '- Upstream version: `${package.version}`',
    '- Package path: `package.path` in `fluoh.yaml`',
    '- Repository URL/path: `repository.git.url` in `fluoh.yaml`',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '- Command help: `fluoh help`, `fluoh help package`, and `fluoh help verify`',
    '',
    '## Adaptation Checklist',
    '',
    '- Confirm the Dart API surface, existing platform implementations, platform-channel or native entry points, permissions, configuration files, example flows, automated tests, and device-only checks before editing.',
    '- Inspect `${package.packagePath}`, `${package.examplePath}`, package tests, example tests, and pubspec constraints.',
    '- Keep assumptions close to the current diff; remove stale notes before release.',
    '',
    ..._adaptationGuardrailLines(),
    ..._singleAdaptationCommandFlowLines(package),
    ..._singlePlatformVerificationLines(package),
    ..._diagnosticsRoutingLines(),
    '## Next Steps',
    '',
    '1. Establish a selected-SDK and native-platform baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds. Include the matching Android/iOS/macOS run command when the example has that platform directory and the local toolchain is available, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for `${package.name}`.',
    '3. Use upstream package tests and existing example tests as the automated baseline before calling the package complete.',
    '4. Keep package tests and example tests deterministic, with `${package.examplePath}` for AI-assisted or manual platform verification when it exists.',
    '5. Run the full automated OHOS loop when an example and local OpenHarmony emulator or device are available: `${package.ohosRunCommand}`. Use `${package.ohosDeviceRunCommand}` for an already connected hdc target. Use `${package.ohosBuildCommand}` as a build-only fallback when no device is available. JSON `nextCommand` and `diagnostics` give the next failure category. Complete and record required OHOS example functional interactions separately because the run command does not click through pages.',
    '6. Run Android, iOS, and macOS regression checks after shared or example changes when their platform directories exist: run `fluoh doctor --project --json --strict`, then use `${package.androidEmulatorRunCommand}` for Android, `${package.iosSimulatorRunCommand}` for iOS, and `${package.macosRunCommand}` for macOS, or add `--device <id>` for already connected targets. iOS builds use `--no-codesign`; document unavailable local Android/Xcode/macOS host toolchains instead of guessing. Add `${package.examplePath}/integration_test/` or AI-assisted interaction evidence for flows beyond launch smoke.',
    '7. Run `fluoh doctor --project --json --strict` when local native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot state is unclear.',
    '8. Commit the implementation checkpoint before release metadata commands; `${package.versionCommand}` requires a clean worktree before it writes metadata.',
    '9. Use `${package.versionCommand}` and update `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change, then commit the release metadata checkpoint.',
    '10. Run final `${package.verifyCommand}`, create the ignored `.fluoh/ai-report-${package.name}-...md`, run `$_reportCheckCommand`, then run `${package.releaseCheckCommand} --report <report-path>` while the tracked worktree is clean.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml` to confirm SDK version, package path, upstream version, current release status, and example location.',
    '2. Baseline: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds with the selected SDK before changing OHOS code. Include `${package.androidRunCommand}`, `${package.iosRunCommand}`, or `${package.macosRunCommand}` when `${package.examplePath}/android`, `${package.examplePath}/ios`, or `${package.examplePath}/macos` exists and local toolchains are available; fix non-OHOS regressions first.',
    '3. Plan: inspect the upstream Dart API and platform implementations, then identify required OHOS entry points, permissions, config files, tests, example flows, and device checks.',
    '4. Implement: add OHOS code under the package path recorded in `fluoh.yaml` without changing upstream public APIs unless upstream requires it.',
    '5. Test: add deterministic automated checks to existing package tests and example tests. Cover arguments, return shape, errors, and platform-channel names when applicable.',
    '6. Example: from `${package.examplePath}` when it exists, run `fluoh sdk use <sdk-version-from-fluoh.yaml> --pub-get` when the IDE link is missing or stale. Extend the example from its existing platforms plus OHOS, including operation, expected result, pass/fail status, and failure hint.',
    '7. Build and run OHOS: use `${package.ohosRunCommand}` to build, auto-sign, install, launch, capture hilog, and classify failures. Then perform required example functional interactions on the emulator or device and record evidence. Fix permission, `reason`, `usedScene`, ArkTS, install, launch, runtime, or interaction diagnostics before release.',
    '8. Check existing platforms: follow the Platform Verification Matrix. Run `${package.androidEmulatorRunCommand}` when an Android example exists, `${package.iosSimulatorRunCommand}` when an iOS example exists, and `${package.macosRunCommand}` when a macOS example exists, or add `--device <id>` for already connected targets. Use `${package.examplePath}/integration_test/` or AI-assisted interaction evidence for scenario coverage beyond launch smoke. Record exact skip reasons for unavailable local toolchains.',
    '9. Release prep: keep `package.release.status: experimental` until the implementation is complete, tested, and ready to be recommended. Run `fluoh deps get` after dependency or metadata changes, run `${package.verifyCommand}`, then commit the implementation checkpoint.',
    '10. Finish: update `FLUOH_CHANGELOG.md`, commit the release metadata checkpoint, run final `${package.verifyCommand}`, create the ignored `.fluoh/ai-report-${package.name}-...md`, run `$_reportCheckCommand`, then run `${package.releaseCheckCommand} --report <report-path>`. Use `${package.releaseCommand}` only after maintainer approval.',
    '',
    '## Release Readiness',
    '',
    '- Public Dart APIs remain compatible with upstream unless upstream changed them.',
    '- Automated package and example tests cover the adapted behavior where practical.',
    '- Device-only behavior and UI interaction flows have an automated `integration_test`, AI-assisted interaction evidence, an explicitly accepted manual result, or a clear remaining blocker.',
    '- `${package.ohosRunCommand}` succeeds when a local emulator is available; otherwise the device-only blocker is documented.',
    '- `${package.androidRunCommand}`, `${package.iosRunCommand}`, and `${package.macosRunCommand}` run smoke checks and integration tests when those platforms exist and local toolchains are available; unavailable toolchains are documented with exact skipped commands and block a `ready` recommendation.',
    '- `FLUOH_CHANGELOG.md`, `fluoh.yaml`, package status, and release version are ready for `${package.releaseCommand}`.',
    '',
    ..._completionReportLines(),
    ..._localCommitCheckpointLines(multiPackage: false),
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

/// Builds the initial generated `FLUOH_CHANGELOG.md` content.
String packageFluohChangelogContent({
  required List<PackageRepositoryDocPackage> packages,
  required String sdkVersion,
  required String releaseVersion,
}) {
  return [
    '# FlutterOH Changelog',
    '',
    for (final package in packages)
      ...packageFluohChangelogEntryLines(
        package: package,
        sdkVersion: sdkVersion,
        releaseVersion: releaseVersion,
      ),
  ].join('\n');
}

/// Builds one generated changelog entry for a package release tag.
List<String> packageFluohChangelogEntryLines({
  required PackageRepositoryDocPackage package,
  required String sdkVersion,
  required String releaseVersion,
}) {
  final tag = packageReleaseTagForPackage(
    packageName: package.name,
    upstreamVersion: package.version,
    sdkVersion: sdkVersion,
    releaseVersion: releaseVersion,
  );
  return [
    '## $tag',
    '',
    '- TODO: Replace this generated placeholder with actual FlutterOH/OHOS release notes before release. Include implemented behavior, verification evidence, and remaining risks for `${package.name}` ${package.version} on Flutter OHOS SDK `$sdkVersion`.',
    '',
  ];
}

/// Returns the separator needed before appending generated Markdown content.
String markdownAppendSeparator(String content) {
  if (content.endsWith('\n\n')) {
    return '';
  }
  if (content.endsWith('\n')) {
    return '\n';
  }
  return '\n\n';
}

const _implementationGuideSectionId = 'package-implementation-guide';
const _agentsInstructionsSectionId = 'package-agents-instructions';
const _readmeAdaptationSectionId = 'package-readme-adaptation';

bool _generatedSectionOwnsFile(String? existing, {required String sectionId}) {
  if (existing == null || existing.trim().isEmpty) {
    return true;
  }
  return _contentWithoutGeneratedSection(
    existing,
    sectionId: sectionId,
  ).trim().isEmpty;
}

String _contentWithGeneratedSection(
  String? existing,
  String generated, {
  required String sectionId,
  required int templateVersion,
}) {
  final block = _generatedSectionBlock(
    generated,
    sectionId: sectionId,
    templateVersion: templateVersion,
  );
  if (existing == null || existing.trim().isEmpty) {
    return block;
  }

  final replaced = _replaceGeneratedSection(
    existing,
    block,
    sectionId: sectionId,
  );
  if (replaced != null) {
    return replaced;
  }

  return '$existing${markdownAppendSeparator(existing)}$block';
}

String _contentWithReadmeGeneratedSection(
  String? existing,
  String generated, {
  required String sectionId,
  required int templateVersion,
  required String fallbackTitle,
}) {
  final block = _generatedSectionBlock(
    generated,
    sectionId: sectionId,
    templateVersion: templateVersion,
  );
  if (existing == null || existing.trim().isEmpty) {
    return '$block\n# $fallbackTitle\n';
  }

  final content = _contentWithoutGeneratedSection(
    existing,
    sectionId: sectionId,
  );
  if (content.trim().isEmpty) {
    return '$block\n# $fallbackTitle\n';
  }
  return '$block${content.startsWith('\n') ? '' : '\n'}$content';
}

String _generatedSectionBlock(
  String content, {
  required String sectionId,
  required int templateVersion,
}) {
  final normalized = content.endsWith('\n') ? content : '$content\n';
  return '${_generatedSectionStart(sectionId, templateVersion)}\n'
      '<!-- This section is generated by fluoh. Do not edit inside this block; '
      'run `fluoh package docs refresh` after updating fluoh.yaml or upgrading '
      'fluoh. -->\n'
      '$normalized${_generatedSectionEnd(sectionId)}\n';
}

String _generatedSectionStart(String sectionId, int templateVersion) =>
    '<!-- fluoh:generated:start id=$sectionId template=$templateVersion -->';

String _generatedSectionEnd(String sectionId) =>
    '<!-- fluoh:generated:end id=$sectionId -->';

String? _replaceGeneratedSection(
  String content,
  String replacement, {
  required String sectionId,
}) {
  final match = _findGeneratedSection(content, sectionId: sectionId);
  if (match == null) {
    return null;
  }
  final afterEnd = match.end + match.endMarker.length;
  final suffixStart =
      afterEnd < content.length && content.codeUnitAt(afterEnd) == 10
      ? afterEnd + 1
      : afterEnd;
  return '${content.substring(0, match.start)}$replacement'
      '${content.substring(suffixStart)}';
}

String _contentWithoutGeneratedSection(
  String content, {
  required String sectionId,
}) {
  final match = _findGeneratedSection(content, sectionId: sectionId);
  if (match == null) {
    return content;
  }
  final afterEnd = match.end + match.endMarker.length;
  final suffixStart =
      afterEnd < content.length && content.codeUnitAt(afterEnd) == 10
      ? afterEnd + 1
      : afterEnd;
  return '${content.substring(0, match.start)}${content.substring(suffixStart)}';
}

_GeneratedSectionMatch? _findGeneratedSection(
  String content, {
  required String sectionId,
}) {
  final startPattern = RegExp(
    '<!-- fluoh:generated:start id=${RegExp.escape(sectionId)} '
    r'template=\d+ -->',
  );
  final startMatch = startPattern.firstMatch(content);
  if (startMatch != null) {
    final endMarker = _generatedSectionEnd(sectionId);
    final end = content.indexOf(endMarker, startMatch.end);
    if (end >= 0) {
      return _GeneratedSectionMatch(
        start: startMatch.start,
        end: end,
        endMarker: endMarker,
      );
    }
  }
  return null;
}

class _GeneratedSectionMatch {
  const _GeneratedSectionMatch({
    required this.start,
    required this.end,
    required this.endMarker,
  });

  final int start;
  final int end;
  final String endMarker;
}
