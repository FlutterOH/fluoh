import 'dart:io';

import 'manifest/package_manifest.dart';

class PackageRepositoryDocPackage {
  const PackageRepositoryDocPackage({
    required this.name,
    required this.version,
    required this.packagePath,
  });

  final String name;
  final String version;
  final String packagePath;

  String get verifyCommand =>
      packagePath == '.' ? 'fluoh verify' : 'fluoh verify --package $name';

  String get ohosRunCommand => packagePath == '.'
      ? 'fluoh run --platform ohos --json'
      : 'fluoh run --platform ohos --package $name --json';

  String get ohosDeviceRunCommand => packagePath == '.'
      ? 'fluoh run --platform ohos --device <id> --json'
      : 'fluoh run --platform ohos --package $name --device <id> --json';

  String get ohosBuildCommand => packagePath == '.'
      ? 'fluoh build --platform ohos --auto-sign --json'
      : 'fluoh build --platform ohos --package $name --auto-sign --json';

  String get androidRunCommand => packagePath == '.'
      ? 'fluoh run --platform android --json'
      : 'fluoh run --platform android --package $name --json';

  String get androidEmulatorRunCommand => androidRunCommand;

  String get iosRunCommand => packagePath == '.'
      ? 'fluoh run --platform ios --json'
      : 'fluoh run --platform ios --package $name --json';

  String get iosSimulatorRunCommand => iosRunCommand;

  String get macosRunCommand => packagePath == '.'
      ? 'fluoh run --platform macos --json'
      : 'fluoh run --platform macos --package $name --json';

  String get releaseCommand => packagePath == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';

  String get statusCommand => packagePath == '.'
      ? 'fluoh package status'
      : 'fluoh package status --package $name';

  String get releaseDryRunCommand => '$releaseCommand --dry-run';

  String get examplePath =>
      packagePath == '.' ? 'example' : '$packagePath/example';
}

Future<void> writeOrReplacePackageImplementationGuide({
  required Directory destination,
  required List<PackageRepositoryDocPackage> packages,
}) async {
  final file = File('${destination.path}/FLUOH.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  final generated = packageImplementationGuideContent(
    packages: packages,
    includeTitle: true,
  );
  await _writeOrReplaceGeneratedSection(file, generated, existing: existing);
}

Future<void> writeOrReplacePackageAgentsInstructions({
  required Directory destination,
  required List<PackageRepositoryDocPackage> packages,
}) async {
  final file = File('${destination.path}/AGENTS.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  final generated = packageAgentsInstructionsContent(
    packages: packages,
    includeTitle: _generatedSectionOwnsFile(existing),
  );

  await _writeOrReplaceGeneratedSection(file, generated, existing: existing);
}

String packageAgentsInstructionsContent({
  required List<PackageRepositoryDocPackage> packages,
  required bool includeTitle,
}) {
  if (packages.length == 1) {
    return _singlePackageAgentsInstructionsContent(
      package: packages.single,
      includeTitle: includeTitle,
    );
  }

  return [
    if (includeTitle) '# AGENTS.md',
    if (includeTitle) '',
    '## FlutterOH Context',
    '',
    'This repository contains OHOS implementations for multiple Flutter packages. Treat `fluoh.yaml` as the source of truth for the current SDK, repository URL, branch, package paths, upstream versions, release versions, and status.',
    '',
    '- Package metadata: `packages.<name>` entries in `fluoh.yaml`.',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`.',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`.',
    '- Release notes: `FLUOH_CHANGELOG.md`.',
    '',
    '## Packages',
    '',
    for (final package in packages)
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, example `${package.examplePath}`, verify command `${package.verifyCommand}`, release command `${package.releaseCommand}`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh deps get` when dependencies may be stale.',
    '- Before adding OHOS code, establish a selected-SDK baseline with `fluoh flutter analyze` and existing package tests or example builds. Fix non-OHOS platform regressions first.',
    '- Keep OHOS implementation changes focused near each package path; preserve upstream APIs and non-OHOS behavior.',
    '- Use upstream package tests and existing example tests as the automated baseline. Extend the package example for manual platform verification when behavior needs a device.',
    '- Treat example apps as real verification surfaces: every important workflow should provide a visible operation, expected result, pass/fail status, and failure hint.',
    '- Prefer the full automated OHOS loop when a local OpenHarmony emulator or device is available: `fluoh run --platform ohos --package <name> --json`. Add `--device <id>` for an already connected hdc target.',
    '- After changing shared Dart code, dependencies, examples, or platform-channel contracts, run existing-platform regression checks when the example has those platforms: `fluoh run --platform android --package <name> --json` for Android, `fluoh run --platform ios --package <name> --json` for iOS, and `fluoh run --platform macos --package <name> --json` for macOS. Add `--emulator <name>` to start a local emulator or simulator where available, or `--device <id>` to select a connected target. iOS builds use `--no-codesign` automatically.',
    '- Run `fluoh doctor --project --json --strict` when native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot health is unclear; fix warnings before editing package logic.',
    '- Read JSON `nextCommand` and `diagnostics` before editing. Use the suggested next command and diagnostic code to decide whether to fix Dart analysis/tests, OHOS build, signing/permissions, target setup, install, launch, or runtime crash behavior.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package paths, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for every package being released.',
    '- When a `fluoh` command or option is unclear, run `fluoh help`, `fluoh help package`, or the command-specific help such as `fluoh help verify` before guessing.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, and schema keys rather than exact prose.',
    '- Do not invent OHOS APIs, permissions, manifest fields, or signing values. Derive them from upstream platform behavior, generated errors, or existing FlutterOH package implementations; stop and ask when the source is unclear.',
    '- Run `${packages.first.verifyCommand}` or another package-specific `fluoh verify --package <name>` before release. Commit before `fluoh package sync`, `fluoh package release --package <name>`, or `fluoh package release --all` because release commands require a clean worktree.',
    '',
    ..._multiAdaptationCommandFlowLines(),
    '## Stop and Ask',
    '',
    '- Ask before changing Dart public APIs, package names, dependency constraints, release versions, repository remotes, or branch layout.',
    '- Ask before deleting upstream files, replacing platform implementations wholesale, force-pushing, running destructive Git commands, or committing failing work.',
    '- If an OHOS API, permission, signing setting, device capability, or generated build error is unclear, report the evidence and the smallest next check instead of guessing.',
    '- Preserve the local worktree on network, GitHub, push, sync, or release failures; summarize the failure and leave retryable next steps.',
    '',
    ..._multiPlatformVerificationLines(),
    ..._diagnosticsRoutingLines(),
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml`, `FLUOH.md`, each package path, `pubspec.yaml`, existing platform implementations, tests, and any package example before editing.',
    '2. Baseline: work one package at a time. Run `fluoh deps get`, `fluoh flutter analyze`, existing package tests, `fluoh doctor --project --json --strict`. Include Android/iOS/macOS run commands when `example/android`, `example/ios`, or `example/macos` exists and the local toolchain is available; fix non-OHOS regressions first.',
    '3. Plan: map the Dart API to platform-channel or native entry points, permissions, configuration files, example flows, automated tests, and device-only checks. State any assumptions before implementing.',
    '4. Implement: add OHOS behavior near the recorded package path while preserving upstream public APIs and non-OHOS behavior.',
    '5. Refresh: run `fluoh deps get` after dependency, SDK, package metadata, or example setup changes. From each existing package example, run `fluoh sdk use <sdk-version> --pub-get` if the IDE link is missing or stale.',
    '6. Test: add or update deterministic package tests and example tests. Cover arguments, return shapes, errors, platform-channel names, and user-visible example flows where applicable.',
    '7. Verify OHOS example: extend each package example from its existing platforms plus OHOS. Run `fluoh run --platform ohos --package <name> --json` when a local emulator is available; use `--device <id>` for an already connected target. This builds, generates temporary debug signing from requested permissions, installs, launches, captures hilog, and reports JSON diagnostics.',
    '8. Verify existing platforms: after OHOS changes, follow the Platform Verification Matrix for each existing platform directory. Build-only evidence is not enough for release readiness; use `fluoh doctor --platform android --json --strict`, `fluoh doctor --platform ios --json --strict`, or `fluoh doctor --platform macos --json --strict` to check native tooling, then use the matching `fluoh run --platform <platform> --package <name> --json` command so Android, iOS, and macOS examples are launched and integration tests run when present. If a local Android, Xcode, device, simulator, or macOS host environment is unavailable, record the exact skipped command and reason in the report.',
    '9. Release prep: keep `packages.<name>.status: experimental` until that package is implemented, tested, and ready to be recommended. Update `FLUOH_CHANGELOG.md` for each package, run the matching `fluoh verify --package <name>`, review `git status --short --ignored=matching`, then commit before `fluoh package release --package <name>` or `fluoh package release --all`.',
    '',
    '## Definition of Done',
    '',
    '- Each package being released has an OHOS implementation that matches upstream behavior for the supported API surface and preserves public Dart APIs unless upstream changed them.',
    '- Automated checks cover the adapted behavior where practical; any device-only verification gap is documented with the reason and the manual check needed.',
    '- Each existing package example exposes visible operations, expected results, pass/fail status, and failure hints for important workflows.',
    '- The matching full OHOS run succeeds when a local emulator or device is available; otherwise the HAP build succeeds and the device-only blocker is documented.',
    '- Existing Android, iOS, and macOS example builds, run smoke checks, and integration tests pass when their platform directories and local toolchains exist; skipped checks include the exact command and environment blocker.',
    '- `FLUOH_CHANGELOG.md` is updated and `packages.<name>.status` remains `experimental` until the package is ready to recommend.',
    '- The matching `fluoh verify --package <name>` succeeds before release.',
    '- A timestamped `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md` exists and gives the maintainer enough context to decide whether to release or request follow-up changes.',
    '',
    ..._completionReportLines(),
    '## Final Response',
    '',
    '- Keep the final response short. Point to the generated `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md`, state whether the package is ready for release, and list only blocking risks or the maintainer decision needed next.',
    '',
    ..._localCommitCheckpointLines(multiPackage: true, packageScope: '<name>'),
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching` and staged files before committing.',
    '- Do not commit local paths, IDE metadata, generated build outputs, caches, certificates, private keys, passwords, or signing profiles.',
    '- Do not commit team-specific iOS signing state such as `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE_SPECIFIER`, profile UUIDs, or non-generic `CODE_SIGN_IDENTITY` values.',
    '- OHOS `signingConfigs` may exist for local testing, but tracked files must not contain real certificate paths, passwords, or private signing material. Commit empty or placeholder signing settings only.',
    '',
  ].join('\n');
}

String _singlePackageAgentsInstructionsContent({
  required PackageRepositoryDocPackage package,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# AGENTS.md',
    if (includeTitle) '',
    '## FlutterOH Context',
    '',
    'This repository contains the OHOS implementation for `${package.name}`. Treat `fluoh.yaml` as the source of truth for the current SDK, repository URL, branch, package path, upstream version, release version, and status.',
    '',
    '- Package metadata: `packages.${package.name}` in `fluoh.yaml`.',
    '- Package path: `packages.${package.name}.repository.path` when present; otherwise `repository.git.path` or `.` in `fluoh.yaml`.',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`.',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`.',
    '- Release notes: `FLUOH_CHANGELOG.md`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh deps get` when dependencies may be stale.',
    '- Before adding OHOS code, establish a selected-SDK baseline with `fluoh flutter analyze` and existing package tests or example builds. Fix non-OHOS platform regressions first.',
    '- Keep OHOS implementation changes focused near the package path recorded in `fluoh.yaml`; preserve upstream APIs and non-OHOS behavior.',
    '- Use upstream package tests and existing example tests as the automated baseline. Extend `${package.examplePath}` for manual platform verification when behavior needs a device.',
    '- Treat example apps as real verification surfaces: every important workflow should provide a visible operation, expected result, pass/fail status, and failure hint.',
    '- Prefer the full automated OHOS loop when a local OpenHarmony emulator or device is available: `${package.ohosRunCommand}`. Use `${package.ohosDeviceRunCommand}` for an already connected hdc target.',
    '- After changing shared Dart code, dependencies, `${package.examplePath}`, or platform-channel contracts, run existing-platform regression checks when the example has those platforms: `${package.androidRunCommand}` for Android, `${package.iosRunCommand}` for iOS, and `${package.macosRunCommand}` for macOS. Add `--emulator <name>` to start a local emulator or simulator where available, or `--device <id>` to select a connected target. iOS builds use `--no-codesign` automatically.',
    '- Run `fluoh doctor --project --json --strict` when native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot health is unclear; fix warnings before editing package logic.',
    '- Read JSON `nextCommand` and `diagnostics` before editing. Use the suggested next command and diagnostic code to decide whether to fix Dart analysis/tests, OHOS build, signing/permissions, target setup, install, launch, or runtime crash behavior.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package path, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for FlutterOH release notes.',
    '- When a `fluoh` command or option is unclear, run `fluoh help`, `fluoh help package`, or the command-specific help such as `fluoh help verify` before guessing.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, and schema keys rather than exact prose.',
    '- Do not invent OHOS APIs, permissions, manifest fields, or signing values. Derive them from upstream platform behavior, generated errors, or existing FlutterOH package implementations; stop and ask when the source is unclear.',
    '- Run `${package.verifyCommand}` before release. Commit before `fluoh package sync` or `${package.releaseCommand}` because release commands require a clean worktree.',
    '',
    ..._singleAdaptationCommandFlowLines(package),
    '## Stop and Ask',
    '',
    '- Ask before changing Dart public APIs, package names, dependency constraints, release versions, repository remotes, or branch layout.',
    '- Ask before deleting upstream files, replacing platform implementations wholesale, force-pushing, running destructive Git commands, or committing failing work.',
    '- If an OHOS API, permission, signing setting, device capability, or generated build error is unclear, report the evidence and the smallest next check instead of guessing.',
    '- Preserve the local worktree on network, GitHub, push, sync, or release failures; summarize the failure and leave retryable next steps.',
    '',
    ..._singlePlatformVerificationLines(package),
    ..._diagnosticsRoutingLines(),
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml`, `FLUOH.md`, `${package.examplePath}` when present, `pubspec.yaml`, existing platform implementations, tests, and the package code path recorded in `fluoh.yaml` before editing.',
    '2. Baseline: run `fluoh deps get`, `fluoh flutter analyze`, existing package tests, `fluoh doctor --project --json --strict` before changing OHOS code. Include `${package.androidRunCommand}`, `${package.iosRunCommand}`, or `${package.macosRunCommand}` when `${package.examplePath}/android`, `${package.examplePath}/ios`, or `${package.examplePath}/macos` exists and the local toolchain is available; fix non-OHOS regressions first.',
    '3. Plan: map the Dart API to platform-channel or native entry points, permissions, configuration files, example flows, automated tests, and device-only checks. State any assumptions before implementing.',
    '4. Implement: add OHOS behavior near the recorded package path while preserving upstream public APIs and non-OHOS behavior.',
    '5. Refresh: run `fluoh deps get` after dependency, SDK, package metadata, or example setup changes. From `${package.examplePath}` when it exists, run `fluoh sdk use <sdk-version-from-fluoh.yaml> --pub-get` if the IDE link is missing or stale.',
    '6. Test: add or update deterministic package tests and example tests. Cover arguments, return shapes, errors, platform-channel names, and user-visible example flows where applicable.',
    '7. Verify OHOS example: extend `${package.examplePath}` from the package\'s existing platforms plus OHOS when an example exists. Run `${package.ohosRunCommand}` when a local emulator is available; use `${package.ohosDeviceRunCommand}` for an already connected target. This builds, generates temporary debug signing from requested permissions, installs, launches, captures hilog, and reports JSON diagnostics.',
    '8. Verify existing platforms: after OHOS changes, follow the Platform Verification Matrix for each existing platform directory. Build-only evidence is not enough for release readiness; use `fluoh doctor --platform android --json --strict`, `fluoh doctor --platform ios --json --strict`, or `fluoh doctor --platform macos --json --strict` to check native tooling, then use `${package.androidEmulatorRunCommand}`, `${package.iosSimulatorRunCommand}`, or `${package.macosRunCommand}` so Android, iOS, and macOS examples are launched and integration tests run when present. If a local Android, Xcode, device, simulator, or macOS host environment is unavailable, record the exact skipped command and reason in the report.',
    '9. Release prep: keep `packages.${package.name}.status: experimental` until the implementation is complete, tested, and ready to be recommended. Update `FLUOH_CHANGELOG.md`, run `${package.verifyCommand}`, review `git status --short --ignored=matching`, then commit before `${package.releaseCommand}`.',
    '',
    '## Definition of Done',
    '',
    '- `${package.name}` has an OHOS implementation that matches upstream behavior for the supported API surface and preserves public Dart APIs unless upstream changed them.',
    '- Automated checks cover the adapted behavior where practical; any device-only verification gap is documented with the reason and the manual check needed.',
    '- `${package.examplePath}` exposes visible operations, expected results, pass/fail status, and failure hints for important workflows when an example exists.',
    '- `${package.ohosRunCommand}` succeeds when a local emulator is available; otherwise `${package.ohosBuildCommand}` succeeds and the device-only blocker is documented.',
    '- `${package.androidRunCommand}`, `${package.iosRunCommand}`, `${package.macosRunCommand}`, run smoke checks, and integration tests pass when their platform directories and local toolchains exist; skipped checks include the exact command and environment blocker.',
    '- `FLUOH_CHANGELOG.md` is updated and `packages.${package.name}.status` remains `experimental` until the package is ready to recommend.',
    '- `${package.verifyCommand}` succeeds before release.',
    '- A timestamped `.fluoh/ai-report-${package.name}-YYYYMMDD-HHMMSS.md` exists and gives the maintainer enough context to decide whether to release or request follow-up changes.',
    '',
    ..._completionReportLines(),
    '## Final Response',
    '',
    '- Keep the final response short. Point to the generated `.fluoh/ai-report-${package.name}-YYYYMMDD-HHMMSS.md`, state whether `${package.name}` is ready for release, and list only blocking risks or the maintainer decision needed next.',
    '',
    ..._localCommitCheckpointLines(multiPackage: false),
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching` and staged files before committing.',
    '- Do not commit local paths, IDE metadata, generated build outputs, caches, certificates, private keys, passwords, or signing profiles.',
    '- Do not commit team-specific iOS signing state such as `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE_SPECIFIER`, profile UUIDs, or non-generic `CODE_SIGN_IDENTITY` values.',
    '- OHOS `signingConfigs` may exist for local testing, but tracked files must not contain real certificate paths, passwords, or private signing material. Commit empty or placeholder signing settings only.',
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
      : '- Use Conventional Commits without a package-name scope when the repository contains only this package, such as `feat: add OHOS platform scaffold` or `test: cover OHOS channel calls`. Use a scope only when it adds real context, such as `docs`, `ci`, `example`, or `release`.';
  return [
    '## Local Commit Checkpoints',
    '',
    '- When the maintainer asks for local commits, create small local commits at completed checkpoints instead of one large final commit.',
    '- Keep commits local unless the maintainer explicitly asks you to push.',
    '- Before the first commit, run `git config --local --get user.name` and `git config --local --get user.email`; if either is missing, ask for author info, then set `git config --local user.name <name>` and `git config --local user.email <email>`. New package repositories can also be created with `fluoh package create --git-author-name <name> --git-author-email <email>`.',
    '- Stage explicit paths for each checkpoint and review `git diff --cached` before committing.',
    '- Commit generated baseline files separately before implementation changes when `fluoh package create` or `fluoh package add` creates the repository or registers a package.',
    '- Suggested checkpoints: generated baseline, selected-SDK baseline fixes, OHOS scaffold, each implemented feature, tests and example verification, then release metadata.',
    '- Commit only after the checkpoint\'s relevant command succeeds; note skipped device-only checks in the commit body.',
    commitScopeGuidance,
    '- Do not commit failing work unless the maintainer explicitly requests a local WIP checkpoint.',
    '',
  ];
}

List<String> _multiAdaptationCommandFlowLines() {
  return [
    '## Automatic Adaptation Command Flow',
    '',
    'Use this command flow as the primary loop. The detailed workflow and platform matrix below add context, but these commands decide when to edit, when to fix local environment, and when the work can be handed back.',
    '',
    '1. Repository setup: use `fluoh package create <upstream>` for a new repository, `fluoh package add <package-path>` for additional packages, and `fluoh package sync` only after a completed, committed checkpoint when upstream needs to be merged.',
    '2. Baseline gates: run `fluoh deps get`, `fluoh doctor --project --json --strict`, `fluoh flutter analyze`, and existing package or example tests before adding OHOS code. Project warnings mean repository fixes; environment warnings mean local toolchain or Source fixes.',
    '3. Implementation loop: after code, dependency, SDK, or metadata changes, rerun `fluoh deps get` when needed, then `fluoh verify --package <name> --json` until pub get, analysis, and existing tests pass.',
    '4. OHOS loop: run `fluoh run --platform ohos --package <name> --json`, or add `--device <id>` for a connected hdc target. If no target is available, run `fluoh build --platform ohos --package <name> --auto-sign --json` as build-only evidence and record the blocker.',
    '5. Existing-platform loop: for Android, run `fluoh doctor --platform android --json --strict`, then `fluoh run --platform android --package <name> --json` when `example/android` exists. For iOS, run `fluoh doctor --platform ios --json --strict`, then `fluoh run --platform ios --package <name> --json` when `example/ios` exists. For macOS, run `fluoh doctor --platform macos --json --strict`, then `fluoh run --platform macos --package <name> --json` when `example/macos` exists.',
    '6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`, `stderrTail`, and saved logs before editing. Fix `doctor` failures in local tooling, project warnings in repository configuration, and verification failures in the package or example that produced the diagnostic.',
    '7. Completion report: create `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md` with command results, platform matrix, signing mode, logs, risks, and release recommendation.',
    '8. Release gate: run `fluoh package status --package <name>`, final `fluoh verify --package <name>`, and `fluoh package release --package <name> --dry-run`. Commit only after the relevant gate succeeds; tag only after maintainer approval.',
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
    '1. Repository setup: use `fluoh package create <upstream>` for a new repository and `fluoh package sync` only after a completed, committed checkpoint when upstream needs to be merged.',
    '2. Baseline gates: run `fluoh deps get`, `fluoh doctor --project --json --strict`, `fluoh flutter analyze`, and existing package or example tests before adding OHOS code. Project warnings mean repository fixes; environment warnings mean local toolchain or Source fixes.',
    '3. Implementation loop: after code, dependency, SDK, or metadata changes, rerun `fluoh deps get` when needed, then `${package.verifyCommand} --json` until pub get, analysis, and existing tests pass.',
    '4. OHOS loop: run `${package.ohosRunCommand}`, or `${package.ohosDeviceRunCommand}` for a connected hdc target. If no target is available, run `${package.ohosBuildCommand}` as build-only evidence and record the blocker.',
    '5. Existing-platform loop: for Android, run `fluoh doctor --platform android --json --strict`, then `${package.androidEmulatorRunCommand}` when `${package.examplePath}/android` exists. For iOS, run `fluoh doctor --platform ios --json --strict`, then `${package.iosSimulatorRunCommand}` when `${package.examplePath}/ios` exists. For macOS, run `fluoh doctor --platform macos --json --strict`, then `${package.macosRunCommand}` when `${package.examplePath}/macos` exists.',
    '6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`, `stderrTail`, and saved logs before editing. Fix `doctor` failures in local tooling, project warnings in repository configuration, and verification failures in the package or example that produced the diagnostic.',
    '7. Completion report: create `.fluoh/ai-report-${package.name}-YYYYMMDD-HHMMSS.md` with command results, platform matrix, signing mode, logs, risks, and release recommendation.',
    '8. Release gate: run `${package.statusCommand}`, final `${package.verifyCommand}`, and `${package.releaseDryRunCommand}`. Commit only after the relevant gate succeeds; tag only after maintainer approval.',
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
    '- For Android/iOS/macOS run smoke checks, `fluoh run` launches the app, waits for Flutter launch output, captures output for `--log-duration`, sends `q`, saves the output under `\$FLUOH_HOME/package-runs`, and reports runtime failures through JSON diagnostics.',
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
    '- For Android/iOS/macOS run smoke checks, `fluoh run` launches the app, waits for Flutter launch output, captures output for `--log-duration`, sends `q`, saves the output under `\$FLUOH_HOME/package-runs`, and reports runtime failures through JSON diagnostics.',
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
    '- `sync.merge_conflict`: upstream merge produced file conflicts. For `fluoh.yaml` metadata conflicts, accept the upstream version and re-apply local package metadata. For OHOS platform files (`ohos/`, platform channels), preserve local OHOS implementations and manually integrate upstream changes. For non-OHOS files, accept upstream. Run `fluoh package sync --continue` after staging resolved files.',
    '- `sync.merge_failed`: git could not merge the upstream branch and did not leave resolvable file conflicts. Inspect `stderrTail`, fix the branch or repository state, then retry `fluoh package sync --json`.',
    '- `sync.fetch_failed`: upstream fetch failed, likely a network issue. Verify network access to the upstream repository, then retry.',
    '',
  ];
}

List<String> _completionReportLines() {
  return [
    '## Completion Report',
    '',
    '- Before final response, create a timestamped report in the repository root using `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md`. Use local time, 24-hour time, and a timestamp precise to seconds, for example `.fluoh/ai-report-camera-20260526-153045.md`. Create `.fluoh/` if needed; it is local state and must not be committed.',
    '- The report must include: package name, upstream version, FlutterOH SDK version, implementation summary, changed files, public API changes if any, permissions and OHOS config changes, commands run with exit results and relevant output tails, final `fluoh run --platform <platform> --json` outcome, a platform matrix for OHOS/Android/iOS/macOS with build, run, integration-test, device/simulator, and skip-blocker fields, signing mode, generated HAP paths, hilog path when present, remaining risks, and release recommendation.',
    '- End the report with one of: `Release recommendation: ready`, `Release recommendation: needs maintainer decision`, or `Release recommendation: blocked`, followed by the exact reason.',
    '- If the maintainer asks for another iteration, create a new timestamped report for that completed iteration so earlier reports remain available.',
    '',
  ];
}

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
    'This repository contains OHOS implementations for multiple Flutter packages. Current SDK, package paths, upstream versions, release versions, and release status are recorded in `fluoh.yaml`.',
    '',
    '## Packages',
    '',
    for (final package in packages)
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, example `${package.examplePath}`, verify command `${package.verifyCommand}`, release command `${package.releaseCommand}`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream packages, FlutterOH repository, SDK target, and release metadata.',
    '- Package metadata: `packages.<name>` entries in `fluoh.yaml`',
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
    ..._multiAdaptationCommandFlowLines(),
    ..._multiPlatformVerificationLines(),
    '## Next Steps',
    '',
    '1. Establish a selected-SDK and native-platform baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds. Include the matching Android/iOS/macOS run command when the example has that platform directory and the local toolchain is available, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for each registered package.',
    '3. Use upstream package tests and existing example tests as the automated baseline before calling the package complete.',
    '4. Keep package tests and example tests deterministic, with existing example apps for manual platform verification.',
    '5. Run the full automated OHOS loop for each package example when a local OpenHarmony emulator or device is available: `fluoh run --platform ohos --package <name> --json`. Add `--device <id>` for an already connected hdc target. Use `fluoh build --platform ohos --package <name> --auto-sign --json` as a build-only fallback when no device is available. JSON `nextCommand` and `diagnostics` give the next failure category.',
    '6. Run Android, iOS, and macOS regression checks after shared or example changes when their platform directories exist: run `fluoh doctor --project --json --strict`, then use `fluoh run --platform android --package <name> --json` for Android, `fluoh run --platform ios --package <name> --json` for iOS, and `fluoh run --platform macos --package <name> --json` for macOS, or add `--device <id>` for already connected targets. iOS builds use `--no-codesign`; document unavailable local Android/Xcode/macOS host toolchains instead of guessing.',
    '7. Run `fluoh doctor --project --json --strict` when local native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot state is unclear.',
    '8. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '9. Run the matching `fluoh verify --package <name>` before release.',
    '10. Commit before `fluoh package sync`, `fluoh package release --package <name>`, or `fluoh package release --all`; release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml` to confirm SDK version, package paths, upstream versions, current release status, and example locations.',
    '2. Baseline: for each package, run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds with the selected SDK before changing OHOS code. Include Android/iOS/macOS run commands when `example/android`, `example/ios`, or `example/macos` exists and local toolchains are available; fix non-OHOS regressions first.',
    '3. Plan: inspect the upstream Dart API and platform implementations, then identify required OHOS entry points, permissions, config files, tests, example flows, and device checks.',
    '4. Implement: add OHOS code without changing upstream public APIs unless upstream requires it.',
    '5. Test: add deterministic automated checks to existing package tests and example tests. Cover arguments, return shape, errors, and platform-channel names when applicable.',
    '6. Example: from each existing package example, run `fluoh sdk use <sdk-version> --pub-get` when the IDE link is missing or stale. Extend examples from their existing platforms plus OHOS, including operation, expected result, pass/fail status, and failure hint.',
    '7. Build and run OHOS: use `fluoh run --platform ohos --package <name> --json` to build, auto-sign, install, launch, capture hilog, and classify failures. Fix permission, `reason`, `usedScene`, ArkTS, install, launch, or runtime diagnostics before release.',
    '8. Check existing platforms: follow the Platform Verification Matrix. Run `fluoh run --platform android --package <name> --json` when an Android example exists, `fluoh run --platform ios --package <name> --json` when an iOS example exists, and `fluoh run --platform macos --package <name> --json` when a macOS example exists, or add `--device <id>` for already connected targets. Record exact skip reasons for unavailable local toolchains.',
    '9. Release prep: keep `packages.<name>.status: experimental` until that package is implemented, tested, and ready to be recommended. Run `fluoh deps get` after dependency or metadata changes, then run the matching `fluoh verify --package <name>`.',
    '10. Finish: update `FLUOH_CHANGELOG.md`, commit, then use `fluoh package release --package <name>` or `fluoh package release --all` for release tagging.',
    '',
    '## Release Readiness',
    '',
    '- Public Dart APIs remain compatible with upstream unless upstream changed them.',
    '- Automated package and example tests cover the adapted behavior where practical.',
    '- Device-only behavior has a manual verification result or a clear remaining blocker.',
    '- The full OHOS run succeeds when a local emulator or device is available; otherwise the device-only blocker is documented.',
    '- Android, iOS, and macOS example builds, run smoke checks, and integration tests pass when those platforms exist and local toolchains are available; unavailable toolchains are documented with exact skipped commands and block a `ready` recommendation.',
    '- `FLUOH_CHANGELOG.md`, `fluoh.yaml`, package status, and release version are ready for `fluoh package release`.',
    '',
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
    '- Package metadata: `packages.${package.name}` in `fluoh.yaml`',
    '- Package path: `packages.${package.name}.repository.path` when present; otherwise `repository.git.path` or `.` in `fluoh.yaml`',
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
    ..._singleAdaptationCommandFlowLines(package),
    ..._singlePlatformVerificationLines(package),
    '## Next Steps',
    '',
    '1. Establish a selected-SDK and native-platform baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds. Include the matching Android/iOS/macOS run command when the example has that platform directory and the local toolchain is available, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for `${package.name}`.',
    '3. Use upstream package tests and existing example tests as the automated baseline before calling the package complete.',
    '4. Keep package tests and example tests deterministic, with `${package.examplePath}` for manual platform verification when it exists.',
    '5. Run the full automated OHOS loop when an example and local OpenHarmony emulator or device are available: `${package.ohosRunCommand}`. Use `${package.ohosDeviceRunCommand}` for an already connected hdc target. Use `${package.ohosBuildCommand}` as a build-only fallback when no device is available. JSON `nextCommand` and `diagnostics` give the next failure category.',
    '6. Run Android, iOS, and macOS regression checks after shared or example changes when their platform directories exist: run `fluoh doctor --project --json --strict`, then use `${package.androidEmulatorRunCommand}` for Android, `${package.iosSimulatorRunCommand}` for iOS, and `${package.macosRunCommand}` for macOS, or add `--device <id>` for already connected targets. iOS builds use `--no-codesign`; document unavailable local Android/Xcode/macOS host toolchains instead of guessing.',
    '7. Run `fluoh doctor --project --json --strict` when local native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot state is unclear.',
    '8. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '9. Run `${package.verifyCommand}` before release.',
    '10. Commit before `fluoh package sync` or `${package.releaseCommand}`; release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml` to confirm SDK version, package path, upstream version, current release status, and example location.',
    '2. Baseline: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds with the selected SDK before changing OHOS code. Include `${package.androidRunCommand}`, `${package.iosRunCommand}`, or `${package.macosRunCommand}` when `${package.examplePath}/android`, `${package.examplePath}/ios`, or `${package.examplePath}/macos` exists and local toolchains are available; fix non-OHOS regressions first.',
    '3. Plan: inspect the upstream Dart API and platform implementations, then identify required OHOS entry points, permissions, config files, tests, example flows, and device checks.',
    '4. Implement: add OHOS code under the package path recorded in `fluoh.yaml` without changing upstream public APIs unless upstream requires it.',
    '5. Test: add deterministic automated checks to existing package tests and example tests. Cover arguments, return shape, errors, and platform-channel names when applicable.',
    '6. Example: from `${package.examplePath}` when it exists, run `fluoh sdk use <sdk-version-from-fluoh.yaml> --pub-get` when the IDE link is missing or stale. Extend the example from its existing platforms plus OHOS, including operation, expected result, pass/fail status, and failure hint.',
    '7. Build and run OHOS: use `${package.ohosRunCommand}` to build, auto-sign, install, launch, capture hilog, and classify failures. Fix permission, `reason`, `usedScene`, ArkTS, install, launch, or runtime diagnostics before release.',
    '8. Check existing platforms: follow the Platform Verification Matrix. Run `${package.androidEmulatorRunCommand}` when an Android example exists, `${package.iosSimulatorRunCommand}` when an iOS example exists, and `${package.macosRunCommand}` when a macOS example exists, or add `--device <id>` for already connected targets. Record exact skip reasons for unavailable local toolchains.',
    '9. Release prep: keep `packages.${package.name}.status: experimental` until the implementation is complete, tested, and ready to be recommended. Run `fluoh deps get` after dependency or metadata changes, then run `${package.verifyCommand}`.',
    '10. Finish: update `FLUOH_CHANGELOG.md`, commit, then use `${package.releaseCommand}` for release tagging.',
    '',
    '## Release Readiness',
    '',
    '- Public Dart APIs remain compatible with upstream unless upstream changed them.',
    '- Automated package and example tests cover the adapted behavior where practical.',
    '- Device-only behavior has a manual verification result or a clear remaining blocker.',
    '- `${package.ohosRunCommand}` succeeds when a local emulator is available; otherwise the device-only blocker is documented.',
    '- `${package.androidRunCommand}`, `${package.iosRunCommand}`, and `${package.macosRunCommand}` run smoke checks and integration tests when those platforms exist and local toolchains are available; unavailable toolchains are documented with exact skipped commands and block a `ready` recommendation.',
    '- `FLUOH_CHANGELOG.md`, `fluoh.yaml`, package status, and release version are ready for `${package.releaseCommand}`.',
    '',
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

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
    '- Initial OHOS implementation for `${package.name}` ${package.version} on Flutter OHOS SDK `$sdkVersion`.',
    '',
  ];
}

String markdownAppendSeparator(String content) {
  if (content.endsWith('\n\n')) {
    return '';
  }
  if (content.endsWith('\n')) {
    return '\n';
  }
  return '\n\n';
}

const _generatedSectionStart = '<!-- fluoh:generated:start -->';
const _generatedSectionEnd = '<!-- fluoh:generated:end -->';

bool _generatedSectionOwnsFile(String? existing) {
  if (existing == null || existing.trim().isEmpty) {
    return true;
  }
  return _contentWithoutGeneratedSection(existing).trim().isEmpty;
}

Future<void> _writeOrReplaceGeneratedSection(
  File file,
  String generated, {
  required String? existing,
}) async {
  final block = _generatedSectionBlock(generated);
  if (existing == null || existing.trim().isEmpty) {
    await file.writeAsString(block);
    return;
  }

  final replaced = _replaceGeneratedSection(existing, block);
  if (replaced != null) {
    await file.writeAsString(replaced);
    return;
  }

  await file.writeAsString(
    '$existing${markdownAppendSeparator(existing)}$block',
  );
}

String _generatedSectionBlock(String content) {
  final normalized = content.endsWith('\n') ? content : '$content\n';
  return '$_generatedSectionStart\n$normalized$_generatedSectionEnd\n';
}

String? _replaceGeneratedSection(String content, String replacement) {
  final start = content.indexOf(_generatedSectionStart);
  if (start < 0) {
    return null;
  }
  final end = content.indexOf(_generatedSectionEnd, start);
  if (end < 0) {
    return null;
  }
  final afterEnd = end + _generatedSectionEnd.length;
  final suffixStart =
      afterEnd < content.length && content.codeUnitAt(afterEnd) == 10
      ? afterEnd + 1
      : afterEnd;
  return '${content.substring(0, start)}$replacement${content.substring(suffixStart)}';
}

String _contentWithoutGeneratedSection(String content) {
  final start = content.indexOf(_generatedSectionStart);
  if (start < 0) {
    return content;
  }
  final end = content.indexOf(_generatedSectionEnd, start);
  if (end < 0) {
    return content;
  }
  final afterEnd = end + _generatedSectionEnd.length;
  final suffixStart =
      afterEnd < content.length && content.codeUnitAt(afterEnd) == 10
      ? afterEnd + 1
      : afterEnd;
  return '${content.substring(0, start)}${content.substring(suffixStart)}';
}
