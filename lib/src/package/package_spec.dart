import 'dart:io';

import 'manifest/package_manifest.dart';

/// Returns the package design/spec path relative to the repository root.
String packageSpecRelativePath(String packageName) {
  return 'doc/fluoh/$packageName/spec.md';
}

/// Returns the branch-local package design/spec file.
File packageSpecFile(Directory repository, String packageName) {
  return File('${repository.path}/${packageSpecRelativePath(packageName)}');
}

/// Writes the initial branch-local package spec when it is missing.
///
/// fluoh creates the spec once. Maintainers and agents own all later edits.
Future<void> writeInitialPackageSpec({
  required Directory repository,
  required PackageManifest manifest,
}) async {
  final file = packageSpecFile(repository, manifest.package.name);
  if (await file.exists()) {
    return;
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(initialPackageSpecContent(manifest));
}

/// Builds the initial package spec content.
String initialPackageSpecContent(PackageManifest manifest) {
  final package = manifest.package;
  final upstreamLines = manifest.isPorted
      ? [
          '- Upstream repository: `${manifest.requiredUpstreamUrl}`',
          '- Upstream branch: `${manifest.upstreamBranch}`',
          '- Upstream version: `${package.requiredUpstreamVersion}`',
          '- Upstream commit: `${package.requiredUpstreamCommit}`',
          if (package.upstreamRef != null)
            '- Upstream ref: `${package.upstreamRef}`',
        ]
      : [
          '- Source: user-maintained package specification',
          '- Source version: `${package.version}`',
        ];
  final baseline = manifest.isPorted
      ? 'Review the upstream README, public Dart API, platform interface, examples, tests, and existing platform implementations before changing platform code.'
      : 'Clarify the user-facing package purpose, public Dart API, target platform matrix, and platform-specific behavior before implementation.';
  final reviewHeading = manifest.isPorted
      ? 'Upstream Review Notes'
      : 'Requirements Notes';
  final followUp = manifest.isPorted
      ? 'Keep the upstream version and commit listed above current after every `fluoh package upstream sync`.'
      : 'Update this spec before implementation when the package purpose, public API, supported platforms, or test expectations change.';
  return '''
# ${package.name} FlutterOH Spec

This branch-local spec is maintained by the maintainer and the fluoh skill. It is not regenerated after creation.
Replace every generated TODO before implementation; `fluoh package next`
reports remaining generated TODOs as spec-review blockers.
Use the bundled fluoh skill `package-spec-template.md` as the fill-in
structure when available.

## Package

- Name: `${package.name}`
- Origin: `${manifest.originKind}`
- Package path: `${package.path}`
- FlutterOH SDK: `${manifest.sdkVersion}`
- Repository branch: `${manifest.branch}`
${upstreamLines.join('\n')}

## Goals

- TODO: Define the user-facing package goal and required platform behavior.

## Public API

- TODO: List the Dart API surface and platform scope for each API.

## Platform Behavior

- TODO: Describe each target platform role: implementation target, preserved baseline, unsupported, not applicable, or manual required.

## Platform API Mapping

- TODO: Map each P0 scope entry to native/platform APIs, permissions, configuration files, device-only constraints, and reviewed sources for every target platform.

## Examples

- TODO: Identify example app flows that demonstrate the supported behavior.

## Tests and Evidence

- TODO: Define unit, integration, example-app, manual-assisted, regression, and device evidence required per platform before delivery.

## $reviewHeading

$baseline

$followUp
''';
}

/// Inspects whether the branch-local package spec exists and matches the
/// current upstream baseline for ported packages.
Future<PackageSpecStatus> inspectPackageSpec({
  required Directory repository,
  required PackageManifest manifest,
}) async {
  final package = manifest.package;
  final path = packageSpecRelativePath(package.name);
  final file = File('${repository.path}/$path');
  if (!await file.exists()) {
    return PackageSpecStatus(
      path: path,
      exists: false,
      reviewRequired: true,
      issues: [
        PackageSpecIssue(
          code: 'spec.missing',
          severity: 'actionRequired',
          message: 'Missing branch-local package spec.',
        ),
      ],
    );
  }

  final content = await file.readAsString();
  final issues = <PackageSpecIssue>[
    ..._generatedSpecTodoIssues(content),
    ..._templatePlaceholderIssues(content),
  ];
  if (manifest.isPorted) {
    final currentCommit = package.requiredUpstreamCommit;
    if (!content.contains(currentCommit)) {
      issues.add(
        PackageSpecIssue(
          code: 'spec.upstream_review_required',
          severity: 'actionRequired',
          message:
              'Spec does not reference the current upstream commit $currentCommit.',
        ),
      );
    }
    final currentVersion = package.requiredUpstreamVersion;
    if (!content.contains(currentVersion)) {
      issues.add(
        PackageSpecIssue(
          code: 'spec.upstream_version_review_required',
          severity: 'actionRequired',
          message:
              'Spec does not reference the current upstream version $currentVersion.',
        ),
      );
    }
  }

  return PackageSpecStatus(
    path: path,
    exists: true,
    reviewRequired: issues.isNotEmpty,
    issues: issues,
  );
}

List<PackageSpecIssue> _generatedSpecTodoIssues(String content) {
  final remaining = [
    for (final line in _generatedSpecTodoLines)
      if (content.contains(line)) line,
  ];
  if (remaining.isEmpty) {
    return const [];
  }
  return [
    PackageSpecIssue(
      code: 'spec.generated_todos_remaining',
      severity: 'actionRequired',
      message:
          'Generated spec TODOs remain. Replace them with the reviewed package contract before implementation.',
    ),
  ];
}

List<PackageSpecIssue> _templatePlaceholderIssues(String content) {
  final remaining = [
    for (final marker in _templatePlaceholderMarkers)
      if (content.contains(marker)) marker,
  ];
  if (remaining.isEmpty) {
    return const [];
  }
  return [
    PackageSpecIssue(
      code: 'spec.template_placeholders_remaining',
      severity: 'actionRequired',
      message:
          'Package spec template placeholders remain. Replace them with reviewed package contract values before implementation.',
    ),
  ];
}

const _generatedSpecTodoLines = [
  '- TODO: Define the user-facing package goal and required platform behavior.',
  '- TODO: List the Dart API surface and platform scope for each API.',
  '- TODO: Describe each target platform role: implementation target, preserved baseline, unsupported, not applicable, or manual required.',
  '- TODO: Map each P0 scope entry to native/platform APIs, permissions, configuration files, device-only constraints, and reviewed sources for every target platform.',
  '- TODO: Identify example app flows that demonstrate the supported behavior.',
  '- TODO: Define unit, integration, example-app, manual-assisted, regression, and device evidence required per platform before delivery.',
];

const _templatePlaceholderMarkers = [
  'SPEC-TODO:',
  '# <package> FlutterOH Spec',
  '| Name | `<package>` |',
  '| Package path | `<package-path>` |',
  '| FlutterOH SDK | `<sdk-version>` |',
  '| SDK line | `<sdk-line>` |',
  'ohos/<sdk-line>/<package>',
  '`<public-api>`',
  '`<scope-entry>`',
  '`<test-or-evidence>`',
];

/// Branch-local package spec inspection result.
class PackageSpecStatus {
  /// Creates a package spec status value.
  const PackageSpecStatus({
    required this.path,
    required this.exists,
    required this.reviewRequired,
    required this.issues,
  });

  /// Spec path relative to the repository root.
  final String path;

  /// Whether the spec file exists.
  final bool exists;

  /// Whether the spec must be updated before the next implementation action.
  final bool reviewRequired;

  /// Spec issues that explain the required action.
  final List<PackageSpecIssue> issues;

  /// JSON representation used by `fluoh package next --json`.
  Map<String, Object?> toJson() {
    return {
      'path': path,
      'exists': exists,
      'reviewRequired': reviewRequired,
      'issues': [for (final issue in issues) issue.toJson()],
    };
  }
}

/// One branch-local package spec issue.
class PackageSpecIssue {
  /// Creates a package spec issue.
  const PackageSpecIssue({
    required this.code,
    required this.severity,
    required this.message,
  });

  /// Stable issue code.
  final String code;

  /// Issue severity.
  final String severity;

  /// Human-readable issue message.
  final String message;

  /// JSON representation used by command output.
  Map<String, Object?> toJson() {
    return {'code': code, 'severity': severity, 'message': message};
  }
}
