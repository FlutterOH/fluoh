import 'dart:io';

import '../workflow/platform_workflow_policy.dart';
import 'package_discovery.dart';
import 'manifest/package_manifest.dart';

part 'package_repository_doc_sections.dart';
part 'package_repository_generated_sections.dart';

/// Package-specific values used when generating repository guidance documents.
class PackageRepositoryDocPackage {
  /// Creates a documentation package descriptor.
  const PackageRepositoryDocPackage({
    required this.name,
    required this.version,
    required this.packagePath,
    this.repositoryUrl,
    this.implementationRecommendation,
  });

  /// Package name from the upstream pubspec.
  final String name;

  /// Upstream package version targeted by the adaptation.
  final String version;

  /// Package path inside the FlutterOH repository.
  final String packagePath;

  /// FlutterOH package repository URL, when known.
  final String? repositoryUrl;

  /// Federated implementation package recommendation, when this package is an
  /// app-facing plugin that should gain a new platform implementation package.
  final PackageImplementationRecommendation? implementationRecommendation;

  /// Recommended package verification command.
  String get verifyCommand =>
      packagePath == '.' ? 'fluoh verify' : 'fluoh verify --package $name';

  String? get _commandPackageName => packagePath == '.' ? null : name;

  String _runCommand(
    String platform, {
    bool startEmulator = false,
    String? deviceId,
  }) {
    return platformWorkflowPolicy(platform).runCommand(
      packageName: _commandPackageName,
      startEmulator: startEmulator,
      deviceId: deviceId,
    );
  }

  String _buildCommand(String platform, {bool autoSign = false}) {
    return platformWorkflowPolicy(
      platform,
    ).buildCommand(packageName: _commandPackageName, autoSign: autoSign);
  }

  /// OHOS run command for default target selection.
  String get ohosRunCommand => _runCommand('ohos', startEmulator: true);

  /// OHOS run command with an explicit connected device placeholder.
  String get ohosDeviceRunCommand => _runCommand('ohos', deviceId: '<id>');

  /// OHOS build command used when no runnable target is available.
  String get ohosBuildCommand => _buildCommand('ohos', autoSign: true);

  /// Android example run command.
  String get androidRunCommand => _runCommand('android', startEmulator: true);

  /// Android emulator run command alias used by generated guidance.
  String get androidEmulatorRunCommand => androidRunCommand;

  /// iOS example run command.
  String get iosRunCommand => _runCommand('ios', startEmulator: true);

  /// iOS simulator run command alias used by generated guidance.
  String get iosSimulatorRunCommand => iosRunCommand;

  /// macOS example run command.
  String get macosRunCommand => _runCommand('macos');

  /// Linux example build command.
  String get linuxBuildCommand => _buildCommand('linux');

  /// Linux example run command.
  String get linuxRunCommand => _runCommand('linux');

  /// Windows example build command.
  String get windowsBuildCommand => _buildCommand('windows');

  /// Windows example run command.
  String get windowsRunCommand => _runCommand('windows');

  /// Web example build command.
  String get webBuildCommand => _buildCommand('web');

  /// Web example run command.
  String get webRunCommand => _runCommand('web');

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
const int packageImplementationGuideTemplateVersion = 2;

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

/// Builds documentation package descriptors from a package manifest and the
/// current checkout.
Future<List<PackageRepositoryDocPackage>>
packageRepositoryDocPackagesForCurrentCheckout({
  required Directory repository,
  required PackageManifest manifest,
}) async {
  final packages = packageRepositoryDocPackagesForManifest(manifest);
  final discovery = await discoverPackageAdaptationCandidates(
    repository: repository,
    missingPlatform: 'ohos',
  );
  return [
    for (final package in packages)
      PackageRepositoryDocPackage(
        name: package.name,
        version: package.version,
        packagePath: package.packagePath,
        repositoryUrl: package.repositoryUrl,
        implementationRecommendation:
            _implementationRecommendationForDocPackage(
              discovery: discovery,
              package: package,
              missingPlatform: 'ohos',
            ),
      ),
  ];
}

PackageImplementationRecommendation?
_implementationRecommendationForDocPackage({
  required PackageDiscovery discovery,
  required PackageRepositoryDocPackage package,
  required String missingPlatform,
}) {
  for (final candidate in discovery.candidates) {
    if (candidate.name == package.name &&
        candidate.path == package.packagePath) {
      return candidate.implementationRecommendation(missingPlatform);
    }
  }
  return null;
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
