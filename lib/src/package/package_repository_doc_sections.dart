part of 'package_repository_docs.dart';

/// Builds generated `FLUOH.md` package context for the fluoh skill.
String packageContextContent({
  required List<PackageRepositoryDocPackage> packages,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# FlutterOH Package Context',
    if (includeTitle) '',
    'Generated quick context for the fluoh skill. Use this file to identify the package, code surfaces, examples, tests, and release history; use fluoh CLI JSON and `nextAction` for workflow state.',
    '',
    ..._packageContextLines(packages),
    ..._ownershipLines(),
    ..._librarySurfaceLines(),
    ..._federatedImplementationRouteLines(packages),
    ..._fluohWorkflowLines(packages),
    ..._deliveryGateLines(),
    ..._flutterOhosReleaseHistoryLines(packages),
  ].join('\n');
}

List<String> _packageContextLines(List<PackageRepositoryDocPackage> packages) {
  if (packages.length == 1) {
    return [
      '## Package',
      '',
      ..._singlePackageContextLines(packages.single),
      '',
    ];
  }
  return [
    '## Packages',
    '',
    for (final package in packages) ...[
      '### ${package.name}',
      '',
      ..._singlePackageContextLines(package),
      '',
    ],
  ];
}

List<String> _singlePackageContextLines(PackageRepositoryDocPackage package) {
  return [
    '- Name: `${package.name}`',
    '- Origin: `${package.originKind}`',
    '- Source version: `${package.version}`',
    '- Package path: `${package.packagePath}`',
    '- Example path: `${package.examplePath}`',
    '- FlutterOH SDK: `${package.sdkVersion ?? '<sdk-version>'}`',
    '- Release version: `${package.releaseVersion ?? '<release-version>'}`',
    if (package.repositoryUrl != null)
      '- Repository: `${package.repositoryUrl}`',
    '- Spec: `${package.specPath}`',
    '- Verify: `${package.verifyCommand}`',
    '- Status: `${package.statusCommand}`',
    '- Release check: `${package.releaseCheckCommand}`',
    '- Release: `${package.releaseCommand}`',
    '- Support scope: `doc/fluoh/${package.name}/scope.yaml`',
  ];
}

List<String> _ownershipLines() {
  return [
    '## Ownership',
    '',
    '- `fluoh.yaml` is the package metadata source of truth.',
    '- `doc/fluoh/<package>/spec.md` is the branch-local contract for requirements, public API, platform behavior, and tests.',
    '- `doc/fluoh/<package>/scope.yaml` records support decisions, test cases, and evidence by scope entry and platform.',
    '- `FLUOH.md` is a generated index. Keep detailed design in the spec and evidence state in the current `.fluoh/tasks/` workspace.',
    '- Upstream README and agent policy files are repository-owned. fluoh does not create, rewrite, or stage them as generated support context.',
    '',
  ];
}

List<String> _librarySurfaceLines() {
  return [
    '## Library Surface',
    '',
    '- Public Dart API, platform interface, method-channel names, error/result shapes, and dependency constraints.',
    '- Existing platform implementations that are present, plus their registration and native configuration files.',
    '- Example app flows, visible labels, permission prompts, status/error states, `test/`, and `integration_test/` coverage.',
    '- Required OHOS/OpenHarmony or vendor SDK APIs, permissions, `reason`/`usedScene` declarations, signing, and device-only behavior.',
    '',
  ];
}

List<String> _federatedImplementationRouteLines(
  List<PackageRepositoryDocPackage> packages,
) {
  final recommended = packages
      .where((package) => package.implementationRecommendation != null)
      .toList();
  if (recommended.isEmpty) {
    return const [];
  }
  return [
    '## Federated Implementation Route',
    '',
    for (final package in recommended) ...[
      ..._singleFederatedImplementationRouteLines(package),
      '',
    ],
  ];
}

List<String> _singleFederatedImplementationRouteLines(
  PackageRepositoryDocPackage package,
) {
  final recommendation = package.implementationRecommendation!;
  return [
    if (package.name != recommendation.appFacingPackage) '### ${package.name}',
    '- Keep the Source route and public API on app-facing package `${recommendation.appFacingPackage}`.',
    '- Create the FlutterOH implementation package `${recommendation.implementationPackageName}` at `${recommendation.implementationPackagePath}`.',
    '- Add `${recommendation.platform}.default_package: ${recommendation.implementationPackageName}` to `${recommendation.appFacingPackage}`.',
    '- Add dependency `${recommendation.implementationPackageName}` with relative path `${recommendation.implementationDependencyPath}`.',
    '- Existing default packages for parity: ${_defaultPackageSummary(recommendation.existingDefaultPackages)}.',
  ];
}

List<String> _fluohWorkflowLines(List<PackageRepositoryDocPackage> packages) {
  if (packages.length == 1) {
    return [
      '## Fluoh Workflow',
      '',
      ..._singleFluohWorkflowLines(packages.single),
      '',
    ];
  }
  return [
    '## Fluoh Workflow',
    '',
    for (final package in packages) ...[
      '### ${package.name}',
      '',
      ..._singleFluohWorkflowLines(package),
      '',
    ],
  ];
}

List<String> _singleFluohWorkflowLines(PackageRepositoryDocPackage package) {
  return [
    '- Start with `${package.nextCommand} --json` and follow exactly one `nextAction` at a time.',
    '- Verify with `${package.verifyCommand} --json`; use build/run/drive commands printed by fluoh JSON as evidence sources.',
    '- Do not maintain a parallel checklist in this file; keep support-scope planning in `doc/fluoh/${package.name}/scope.yaml` and final evidence in the current `.fluoh/tasks/` workspace.',
    '- Run `${package.releaseCheckCommand} --report <report-path> --json` only after the implementation loop is ready.',
  ];
}

List<String> _deliveryGateLines() {
  return [
    '## Delivery Gates',
    '',
    '- Upstream public API compatibility is preserved or the report records the required maintainer decision.',
    '- Platform implementation, example behavior, permissions/configuration, preserved baselines, and device-only paths have tool-readable evidence.',
    '- Existing platform examples and tests are checked when their platform directories and local toolchains are available.',
    '- `FlutterOH Release History` contains real release notes before release.',
    '',
  ];
}

String _defaultPackageSummary(Map<String, String> packages) {
  return packages.entries
      .map((entry) => '${entry.key} -> ${entry.value}')
      .join(', ');
}

List<String> _flutterOhosReleaseHistoryLines(
  List<PackageRepositoryDocPackage> packages,
) {
  return [
    '## FlutterOH Release History',
    '',
    for (final package in packages)
      ...packageFlutterOhosReleaseHistoryEntryLines(package: package),
  ];
}

/// Builds one generated release history entry for a package release tag.
List<String> packageFlutterOhosReleaseHistoryEntryLines({
  required PackageRepositoryDocPackage package,
}) {
  final sdkVersion = package.sdkVersion ?? '<sdk-version>';
  final releaseVersion = package.releaseVersion ?? '<release-version>';
  final tag = package.originKind == packageOriginCreated
      ? createdPackageReleaseTagForPackage(
          packageName: package.name,
          sdkVersion: sdkVersion,
          releaseVersion: releaseVersion,
        )
      : portedPackageReleaseTagForPackage(
          packageName: package.name,
          upstreamVersion: package.version,
          sdkVersion: sdkVersion,
          releaseVersion: releaseVersion,
        );
  return [
    '### $tag',
    '',
    '- TODO: Replace this generated placeholder with actual FlutterOH release notes before release. Include implemented behavior, verification evidence, and remaining risks for `${package.name}` ${package.version} on FlutterOH SDK `$sdkVersion`.',
    '',
  ];
}
