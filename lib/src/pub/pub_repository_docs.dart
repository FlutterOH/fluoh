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
}

Future<void> writeOrAppendPubAgentsInstructions({
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
    includeTitle: existing == null || existing.trim().isEmpty,
  );

  if (existing == null || existing.trim().isEmpty) {
    await file.writeAsString(generated);
    return;
  }

  await file.writeAsString(
    '$existing${markdownAppendSeparator(existing)}$generated',
  );
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
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, tests `${package.testWorkspacePath}`, release command `${_releaseCommand(package.name)}`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh pub get` when dependencies may be stale.',
    '- Keep OHOS implementation changes focused near each package path; preserve upstream APIs and non-OHOS behavior.',
    '- Keep each package-specific `fluoh_test/<package>/test` for automated platform implementation checks and `fluoh_test/<package>/example` for manual platform verification.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package paths, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for every package being released.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, schema keys, and deprecated terms rather than exact prose.',
    '- Run `${packages.first.testRunCommand}` or another package-specific `fluoh test run --package <name>` before release. Commit before `fluoh pub sync` or `fluoh pub release` because both require a clean worktree.',
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
    '- Keep OHOS implementation changes focused near `${package.packagePath}`; preserve upstream APIs and non-OHOS behavior.',
    '- Keep `${package.testWorkspacePath}/test` for automated platform implementation checks and `${package.testWorkspacePath}/example` for manual platform verification.',
    '- Keep `fluoh.yaml` aligned with SDK, repository URL, branch, package path, release version, upstream version, and status changes.',
    '- Update `FLUOH_CHANGELOG.md` for FlutterOH release notes.',
    '- Keep tests focused on behavior and release contracts. For documentation or generated guidance, assert stable commands, files, schema keys, and deprecated terms rather than exact prose.',
    '- Run `${package.testRunCommand}` before release. Commit before `fluoh pub sync` or `fluoh pub release` because both require a clean worktree.',
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
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, tests `${package.testWorkspacePath}`, release command `${_releaseCommand(package.name)}`.',
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
    '1. Implement the OHOS platform code for each registered package.',
    '2. Keep package-specific `fluoh_test/<package>/test` directories for automated checks and `fluoh_test/<package>/example` apps for manual verification.',
    '3. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '4. Run the matching `fluoh test run --package <name>` before release.',
    '5. Commit before `fluoh pub sync` or `fluoh pub release`; both require a clean worktree.',
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
    '1. Implement the OHOS platform code for `${package.name}`.',
    '2. Keep `${package.testWorkspacePath}/test` for automated checks and `${package.testWorkspacePath}/example` for manual verification.',
    '3. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change.',
    '4. Run `${package.testRunCommand}` before release.',
    '5. Commit before `fluoh pub sync` or `fluoh pub release`; both require a clean worktree.',
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

String _releaseCommand(String packageName) =>
    'fluoh pub release --package $packageName';
