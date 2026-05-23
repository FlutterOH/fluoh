import 'dart:io';

import 'manifest/pub_manifest.dart';

class PubRepositoryDocPackage {
  const PubRepositoryDocPackage({
    required this.name,
    required this.version,
    required this.packagePath,
    required this.testWorkspacePath,
  });

  final String name;
  final String version;
  final String packagePath;
  final String testWorkspacePath;

  String get testRunCommand => testWorkspacePath == 'fluoh_test'
      ? 'fluoh test run'
      : 'fluoh test run --package $name';

  String get releaseCommand => testWorkspacePath == 'fluoh_test'
      ? 'fluoh pub release'
      : 'fluoh pub release --package $name';
}

Future<void> writeOrReplacePubImplementationGuide({
  required Directory destination,
  required List<PubRepositoryDocPackage> packages,
  required String upstreamBranch,
  required String sdkVersion,
  required String branch,
}) async {
  final file = File('${destination.path}/FLUOH.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  final generated = pubImplementationGuideContent(
    packages: packages,
    upstreamBranch: upstreamBranch,
    sdkVersion: sdkVersion,
    branch: branch,
    includeTitle: true,
  );
  await _writeOrReplaceGeneratedSection(file, generated, existing: existing);
}

Future<void> writeOrReplacePubAgentsInstructions({
  required Directory destination,
  required List<PubRepositoryDocPackage> packages,
  required String upstreamBranch,
  required String sdkVersion,
  required String branch,
}) async {
  final file = File('${destination.path}/AGENTS.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  final generated = pubAgentsInstructionsContent(
    packages: packages,
    upstreamBranch: upstreamBranch,
    sdkVersion: sdkVersion,
    branch: branch,
    includeTitle: _generatedSectionOwnsFile(existing),
  );

  await _writeOrReplaceGeneratedSection(file, generated, existing: existing);
}

String pubAgentsInstructionsContent({
  required List<PubRepositoryDocPackage> packages,
  required String upstreamBranch,
  required String sdkVersion,
  required String branch,
  required bool includeTitle,
}) {
  if (packages.length == 1) {
    return _singlePackageAgentsInstructionsContent(
      package: packages.single,
      upstreamBranch: upstreamBranch,
      sdkVersion: sdkVersion,
      branch: branch,
      includeTitle: includeTitle,
    );
  }

  return [
    if (includeTitle) '# AGENTS.md',
    if (includeTitle) '',
    '## FlutterOH Context',
    '',
    'This repository provides OHOS implementations for multiple packages on Flutter OHOS SDK `$sdkVersion`.',
    '',
    '- Upstream branch at creation: `$upstreamBranch`',
    '- FlutterOH branch: `$branch`',
    '- Metadata: `fluoh.yaml`.',
    '- Release notes: `FLUOH_CHANGELOG.md`.',
    '',
    '## Packages',
    '',
    for (final package in packages)
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, tests `${package.testWorkspacePath}`, release command `${package.releaseCommand}`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh pub get` when dependencies may be stale.',
    '- Before adding OHOS code, establish a selected-SDK baseline with `fluoh flutter analyze` and existing package tests or example builds. Fix non-OHOS platform regressions first.',
    '- Keep OHOS implementation changes focused near each package path; preserve upstream APIs and non-OHOS behavior.',
    '- Keep each package-specific `fluoh_test/<package>/test` for automated platform implementation checks and `fluoh_test/<package>/example` for manual platform verification.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package paths, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for every package being released.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, schema keys, and deprecated terms rather than exact prose.',
    '- Run `${packages.first.testRunCommand}` or another package-specific `fluoh test run --package <name>` before release. Commit before `fluoh pub sync`, `fluoh pub release --package <name>`, or `fluoh pub release --all` because release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml`, `FLUOH.md`, each package path, and each matching `fluoh_test/<package>/README.md` before editing.',
    '2. Work one package at a time. Before changing OHOS code, run `fluoh pub get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform code, then implement OHOS behavior without changing public APIs unless upstream requires it.',
    '4. Run `fluoh pub get` after dependency, SDK, or package metadata changes.',
    '5. Add or update automated checks in the matching `fluoh_test/<package>/test` directory. Keep them deterministic and runnable with `fluoh test run --package <name>`.',
    '6. Extend the matching `fluoh_test/<package>/example` app with the smallest UI needed for manual OHOS verification when device behavior cannot be covered by tests.',
    '7. Keep `packages.<name>.status: experimental` until that package is implemented, tested, and ready to be recommended. Remove the status only for a release-ready package.',
    '8. Update `FLUOH_CHANGELOG.md` for each package, run the matching `fluoh test run --package <name>`, review `git status --short --ignored=matching`, then commit before `fluoh pub release --package <name>` or `fluoh pub release --all`.',
    '',
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
  required PubRepositoryDocPackage package,
  required String upstreamBranch,
  required String sdkVersion,
  required String branch,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# AGENTS.md',
    if (includeTitle) '',
    '## FlutterOH Context',
    '',
    'This repository provides an OHOS implementation for `${package.name}` ${package.version} on Flutter OHOS SDK `$sdkVersion`.',
    '',
    '- Package path: `${package.packagePath}`.',
    '- Upstream branch at creation: `$upstreamBranch`',
    '- FlutterOH branch: `$branch`',
    '- Metadata: `fluoh.yaml`.',
    '- Release notes: `FLUOH_CHANGELOG.md`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh pub get` when dependencies may be stale.',
    '- Before adding OHOS code, establish a selected-SDK baseline with `fluoh flutter analyze` and existing package tests or example builds. Fix non-OHOS platform regressions first.',
    '- Keep OHOS implementation changes focused near `${package.packagePath}`; preserve upstream APIs and non-OHOS behavior.',
    '- Keep `${package.testWorkspacePath}/test` for automated platform implementation checks and `${package.testWorkspacePath}/example` for manual platform verification.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package path, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for FlutterOH release notes.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, schema keys, and deprecated terms rather than exact prose.',
    '- Run `${package.testRunCommand}` before release. Commit before `fluoh pub sync` or `${package.releaseCommand}` because release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml`, `FLUOH.md`, `${package.testWorkspacePath}/README.md`, and the package code under `${package.packagePath}` before editing.',
    '2. Before changing OHOS code, run `fluoh pub get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform code, then implement OHOS behavior without changing public APIs unless upstream requires it.',
    '4. Run `fluoh pub get` after dependency, SDK, or package metadata changes.',
    '5. Add or update automated checks in `${package.testWorkspacePath}/test`. Keep them deterministic and runnable with `${package.testRunCommand}`.',
    '6. Extend `${package.testWorkspacePath}/example` with the smallest UI needed for manual OHOS verification when device behavior cannot be covered by tests.',
    '7. Keep `packages.${package.name}.status: experimental` until the implementation is complete, tested, and ready to be recommended. Remove the status only for a release-ready package.',
    '8. Update `FLUOH_CHANGELOG.md`, run `${package.testRunCommand}`, review `git status --short --ignored=matching`, then commit before `${package.releaseCommand}`.',
    '',
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching` and staged files before committing.',
    '- Do not commit local paths, IDE metadata, generated build outputs, caches, certificates, private keys, passwords, or signing profiles.',
    '- Do not commit team-specific iOS signing state such as `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE_SPECIFIER`, profile UUIDs, or non-generic `CODE_SIGN_IDENTITY` values.',
    '- OHOS `signingConfigs` may exist for local testing, but tracked files must not contain real certificate paths, passwords, or private signing material. Commit empty or placeholder signing settings only.',
    '',
  ].join('\n');
}

String pubImplementationGuideContent({
  required List<PubRepositoryDocPackage> packages,
  required String upstreamBranch,
  required String sdkVersion,
  required String branch,
  required bool includeTitle,
}) {
  if (packages.length == 1) {
    return _singlePackageImplementationGuideContent(
      package: packages.single,
      upstreamBranch: upstreamBranch,
      sdkVersion: sdkVersion,
      branch: branch,
      includeTitle: includeTitle,
    );
  }

  return [
    if (includeTitle) '# FlutterOH Implementation',
    if (includeTitle) '',
    'This repository provides OHOS implementations for multiple packages on Flutter OHOS SDK `$sdkVersion`.',
    '',
    '## Packages',
    '',
    for (final package in packages)
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, tests `${package.testWorkspacePath}`, release command `${package.releaseCommand}`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream packages, FlutterOH repository, SDK target, and release metadata.',
    '- Upstream branch: `$upstreamBranch`',
    '- FlutterOH branch: `$branch`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '',
    '## Next Steps',
    '',
    '1. Establish a selected-SDK baseline before adding OHOS code: run `fluoh pub get`, `fluoh flutter analyze`, and existing package tests or example builds, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for each registered package.',
    '3. Keep package-specific `fluoh_test/<package>/test` directories for automated checks and `fluoh_test/<package>/example` apps for manual verification.',
    '4. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '5. Run the matching `fluoh test run --package <name>` before release.',
    '6. Commit before `fluoh pub sync`, `fluoh pub release --package <name>`, or `fluoh pub release --all`; release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml` to confirm SDK version, package paths, upstream versions, and current release status.',
    '2. For each package, run `fluoh pub get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK before changing OHOS code; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform implementations before changing OHOS code.',
    '4. Add deterministic automated checks under the matching `fluoh_test/<package>/test` directory.',
    '5. Add focused manual verification actions to the matching `fluoh_test/<package>/example` app when device behavior needs manual confirmation.',
    '6. Keep `packages.<name>.status: experimental` until that package is implemented, tested, and ready to be recommended.',
    '7. Run `fluoh pub get` after dependency or metadata changes, then run the matching `fluoh test run --package <name>`.',
    '8. Update `FLUOH_CHANGELOG.md`, commit, then use `fluoh pub release --package <name>` or `fluoh pub release --all` for release tagging.',
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
  required PubRepositoryDocPackage package,
  required String upstreamBranch,
  required String sdkVersion,
  required String branch,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# FlutterOH Implementation',
    if (includeTitle) '',
    'This repository provides an OHOS implementation for `${package.name}` ${package.version} on Flutter OHOS SDK `$sdkVersion`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package path: `${package.packagePath}`',
    '- Upstream branch: `$upstreamBranch`',
    '- FlutterOH branch: `$branch`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '',
    '## Next Steps',
    '',
    '1. Establish a selected-SDK baseline before adding OHOS code: run `fluoh pub get`, `fluoh flutter analyze`, and existing package tests or example builds, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for `${package.name}`.',
    '3. Keep `${package.testWorkspacePath}/test` for automated checks and `${package.testWorkspacePath}/example` for manual verification.',
    '4. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '5. Run `${package.testRunCommand}` before release.',
    '6. Commit before `fluoh pub sync` or `${package.releaseCommand}`; release commands require a clean worktree.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Read `fluoh.yaml` to confirm SDK version, package path, upstream version, and current release status.',
    '2. Run `fluoh pub get`, `fluoh flutter analyze`, and existing package tests or example builds with the selected SDK before changing OHOS code; fix non-OHOS regressions first.',
    '3. Inspect the upstream Dart API and platform implementations before changing OHOS code under `${package.packagePath}`.',
    '4. Add deterministic automated checks under `${package.testWorkspacePath}/test`.',
    '5. Add focused manual verification actions to `${package.testWorkspacePath}/example` when device behavior needs manual confirmation.',
    '6. Keep `packages.${package.name}.status: experimental` until the implementation is complete, tested, and ready to be recommended.',
    '7. Run `fluoh pub get` after dependency or metadata changes, then run `${package.testRunCommand}`.',
    '8. Update `FLUOH_CHANGELOG.md`, commit, then use `${package.releaseCommand}` for release tagging.',
    '',
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

String pubFluohChangelogContent({
  required List<PubRepositoryDocPackage> packages,
  required String sdkVersion,
  required String releaseVersion,
}) {
  return [
    '# FlutterOH Changelog',
    '',
    for (final package in packages)
      ...pubFluohChangelogEntryLines(
        package: package,
        sdkVersion: sdkVersion,
        releaseVersion: releaseVersion,
      ),
  ].join('\n');
}

List<String> pubFluohChangelogEntryLines({
  required PubRepositoryDocPackage package,
  required String sdkVersion,
  required String releaseVersion,
}) {
  final tag = pubReleaseTagForPackage(
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
