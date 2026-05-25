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

  String get checkCommand => packagePath == '.'
      ? 'fluoh package check'
      : 'fluoh package check --package $name';

  String get releaseCommand => packagePath == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';

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
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, example `${package.examplePath}`, check command `${package.checkCommand}`, release command `${package.releaseCommand}`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh deps get` when dependencies may be stale.',
    '- Before adding OHOS code, establish a selected-SDK baseline with `fluoh flutter analyze` and existing package tests or example builds. Fix non-OHOS platform regressions first.',
    '- Keep OHOS implementation changes focused near each package path; preserve upstream APIs and non-OHOS behavior.',
    '- Use upstream package tests and existing example tests as the automated baseline. Extend the package example for manual platform verification when behavior needs a device.',
    '- Treat example apps as real verification surfaces: every important workflow should provide a visible operation, expected result, pass/fail status, and failure hint.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package paths, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for every package being released.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, and schema keys rather than exact prose.',
    '- Run `${packages.first.checkCommand}` or another package-specific `fluoh package check --package <name>` before release. Commit before `fluoh package sync`, `fluoh package release --package <name>`, or `fluoh package release --all` because release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml`, `FLUOH.md`, each package path, and any existing package example before editing.',
    '2. Work one package at a time. Before changing OHOS code, run `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform code, then implement OHOS behavior without changing public APIs unless upstream requires it.',
    '4. Run `fluoh deps get` after dependency, SDK, or package metadata changes.',
    '5. From each existing package example, run `fluoh sdk use <sdk-version> --pub-get` if the IDE link is missing or stale; `fluoh package create` pins Flutter examples to the target SDK and adds OHOS when possible.',
    '6. Add or update existing package tests and example tests. Cover arguments, return shapes, errors, platform-channel names, and user-visible example flows where applicable.',
    '7. Extend each package example from its existing platforms plus OHOS. Every important workflow should have a visible operation, expected result, pass/fail status, and failure hint.',
    '8. Build the verification app with `fluoh flutter build hap --debug`; if it stops at signing, configure DevEco Studio debug signing and rerun. If it fails earlier, fix permissions, `reason`, `usedScene`, ArkTS, or package setup before release.',
    '9. Keep `packages.<name>.status: experimental` until that package is implemented, tested, and ready to be recommended. Remove the status only for a release-ready package.',
    '10. Update `FLUOH_CHANGELOG.md` for each package, run the matching `fluoh package check --package <name>`, review `git status --short --ignored=matching`, then commit before `fluoh package release --package <name>` or `fluoh package release --all`.',
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
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package path, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for FlutterOH release notes.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, and schema keys rather than exact prose.',
    '- Run `${package.checkCommand}` before release. Commit before `fluoh package sync` or `${package.releaseCommand}` because release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml`, `FLUOH.md`, `${package.examplePath}` when present, and the package code path recorded in `fluoh.yaml` before editing.',
    '2. Before changing OHOS code, run `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform code, then implement OHOS behavior without changing public APIs unless upstream requires it.',
    '4. Run `fluoh deps get` after dependency, SDK, or package metadata changes.',
    '5. From `${package.examplePath}` when it exists, run `fluoh sdk use <sdk-version-from-fluoh.yaml> --pub-get` if the IDE link is missing or stale; `fluoh package create` pins Flutter examples to the target SDK and adds OHOS when possible.',
    '6. Add or update existing package tests and example tests. Cover arguments, return shapes, errors, platform-channel names, and user-visible example flows where applicable.',
    '7. Extend `${package.examplePath}` from the package\'s existing platforms plus OHOS when an example exists. Every important workflow should have a visible operation, expected result, pass/fail status, and failure hint.',
    '8. Build the verification app with `fluoh flutter build hap --debug`; if it stops at signing, configure DevEco Studio debug signing and rerun. If it fails earlier, fix permissions, `reason`, `usedScene`, ArkTS, or package setup before release.',
    '9. Keep `packages.${package.name}.status: experimental` until the implementation is complete, tested, and ready to be recommended. Remove the status only for a release-ready package.',
    '10. Update `FLUOH_CHANGELOG.md`, run `${package.checkCommand}`, review `git status --short --ignored=matching`, then commit before `${package.releaseCommand}`.',
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
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, example `${package.examplePath}`, check command `${package.checkCommand}`, release command `${package.releaseCommand}`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream packages, FlutterOH repository, SDK target, and release metadata.',
    '- Package metadata: `packages.<name>` entries in `fluoh.yaml`',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '',
    '## Next Steps',
    '',
    '1. Establish a selected-SDK baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or example builds, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for each registered package.',
    '3. Use upstream package tests and existing example tests as the automated baseline before calling the package complete.',
    '4. Keep package tests and example tests deterministic, with existing example apps for manual platform verification.',
    '5. Build each verification app with `fluoh flutter build hap --debug`; signing-only failures are local setup, earlier failures must be fixed.',
    '6. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '7. Run the matching `fluoh package check --package <name>` before release.',
    '8. Commit before `fluoh package sync`, `fluoh package release --package <name>`, or `fluoh package release --all`; release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml` to confirm SDK version, package paths, upstream versions, and current release status.',
    '2. For each package, run `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK before changing OHOS code; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform implementations before changing OHOS code.',
    '4. Add deterministic automated checks to existing package tests and example tests. Cover arguments, return shape, errors, and platform-channel names when applicable.',
    '5. From each existing package example, run `fluoh sdk use <sdk-version> --pub-get` when the IDE link is missing or stale.',
    '6. Extend existing package examples from their existing platforms plus OHOS. Each important workflow should provide an operation, expected result, pass/fail status, and failure hint.',
    '7. Run `fluoh flutter build hap --debug` from the example; fix permission, `reason`, `usedScene`, ArkTS, or package setup failures before release.',
    '8. Keep `packages.<name>.status: experimental` until that package is implemented, tested, and ready to be recommended.',
    '9. Run `fluoh deps get` after dependency or metadata changes, then run the matching `fluoh package check --package <name>`.',
    '10. Update `FLUOH_CHANGELOG.md`, commit, then use `fluoh package release --package <name>` or `fluoh package release --all` for release tagging.',
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
    '',
    '## Next Steps',
    '',
    '1. Establish a selected-SDK baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or example builds, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for `${package.name}`.',
    '3. Use upstream package tests and existing example tests as the automated baseline before calling the package complete.',
    '4. Keep package tests and example tests deterministic, with `${package.examplePath}` for manual platform verification when it exists.',
    '5. Build `${package.examplePath}` with `fluoh flutter build hap --debug` when an example exists; signing-only failures are local setup, earlier failures must be fixed.',
    '6. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '7. Run `${package.checkCommand}` before release.',
    '8. Commit before `fluoh package sync` or `${package.releaseCommand}`; release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml` to confirm SDK version, package path, upstream version, and current release status.',
    '2. Run `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK before changing OHOS code; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform implementations before changing OHOS code under the package path recorded in `fluoh.yaml`.',
    '4. Add deterministic automated checks to existing package tests and example tests. Cover arguments, return shape, errors, and platform-channel names when applicable.',
    '5. From `${package.examplePath}` when it exists, run `fluoh sdk use <sdk-version-from-fluoh.yaml> --pub-get` when the IDE link is missing or stale.',
    '6. Extend `${package.examplePath}` from the package\'s existing platforms plus OHOS when an example exists. Each important workflow should provide an operation, expected result, pass/fail status, and failure hint.',
    '7. Run `fluoh flutter build hap --debug` from `${package.examplePath}` when an example exists; fix permission, `reason`, `usedScene`, ArkTS, or package setup failures before release.',
    '8. Keep `packages.${package.name}.status: experimental` until the implementation is complete, tested, and ready to be recommended.',
    '9. Run `fluoh deps get` after dependency or metadata changes, then run `${package.checkCommand}`.',
    '10. Update `FLUOH_CHANGELOG.md`, commit, then use `${package.releaseCommand}` for release tagging.',
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
