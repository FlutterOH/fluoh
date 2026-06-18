part of 'package_port_command.dart';

class _PackagePortPlan {
  const _PackagePortPlan({
    required this.upstream,
    required this.upstreamBranch,
    required this.repositoryName,
    required this.repositoryUrl,
    required this.outputPath,
    required this.sdkVersion,
    required this.sdkLine,
    required this.packageName,
    required this.packagePath,
    required this.upstreamVersion,
    required this.upstreamRef,
    required this.upstreamCommit,
    required this.branch,
    required this.gitAuthor,
    required this.flutterCreateOrg,
    required this.supportProfile,
    required this.implementationRecommendation,
    required this.warnings,
  });

  final String upstream;
  final String upstreamBranch;
  final String repositoryName;
  final String repositoryUrl;
  final String outputPath;
  final String sdkVersion;
  final String sdkLine;
  final String packageName;
  final String packagePath;
  final String upstreamVersion;
  final String? upstreamRef;
  final String upstreamCommit;
  final String branch;
  final PackageGitAuthor? gitAuthor;
  final String? flutterCreateOrg;
  final PackageSupportProfile supportProfile;
  final PackageImplementationRecommendation? implementationRecommendation;
  final List<_PackagePortWarning> warnings;

  Map<String, Object?> toJson() {
    return {
      'supportKind': 'package',
      'upstream': {
        'urlOrPath': upstream,
        'branch': upstreamBranch,
        'selectedRef': upstreamRef,
        'selectedCommit': upstreamCommit,
      },
      'repository': {
        'name': repositoryName,
        'url': repositoryUrl,
        'outputPath': outputPath,
        'branch': branch,
      },
      'sdk': {'version': sdkVersion, 'line': sdkLine},
      'package': {
        'name': packageName,
        'path': packagePath,
        'upstreamVersion': upstreamVersion,
        'releaseVersion': initialPackageReleaseVersion,
        'status': 'experimental',
      },
      'gitAuthor': gitAuthor == null
          ? null
          : {'name': gitAuthor!.name, 'email': gitAuthor!.email},
      'flutterCreateOrg': flutterCreateOrg,
      'supportProfile': supportProfile.toJson(),
      'implementationRecommendation': ?implementationRecommendation?.toJson(),
      'warnings': warnings.map((warning) => warning.toJson()).toList(),
      'willRun': [
        'git clone <upstream> <outputPath>',
        'configure origin remote',
        if (gitAuthor != null) 'configure local Git author',
        'checkout $branch',
        'configure FlutterOH SDK $sdkVersion',
        'write fluoh.yaml, FLUOH.md, and doc/fluoh/$packageName/spec.md',
        'prepare example OHOS platform when an example exists',
        'stage generated files',
      ],
      'willNotRunWithoutSeparateApproval': [
        'fluoh package release',
        'git push',
        'git push --force',
        'destructive Git commands',
      ],
    };
  }
}

abstract class _PackagePortWarning {
  String get message;
  String get nextStep;
  Map<String, Object?> toJson();
}

class _SdkCompatibilityPlanWarning implements _PackagePortWarning {
  const _SdkCompatibilityPlanWarning(this.warning);

  final PackageSdkCompatibilityWarning warning;

  @override
  String get message => warning.message;

  @override
  String get nextStep => warning.nextStep;

  @override
  Map<String, Object?> toJson() => warning.toJson();
}

class _DefaultBranchPackageVersionWarning implements _PackagePortWarning {
  const _DefaultBranchPackageVersionWarning({
    required this.packageName,
    required this.packagePath,
    required this.selectedRef,
    required this.selectedVersion,
    required this.defaultBranch,
    required this.defaultBranchVersion,
  });

  final String packageName;
  final String packagePath;
  final String selectedRef;
  final String selectedVersion;
  final String defaultBranch;
  final String defaultBranchVersion;

  @override
  String get message =>
      'Default branch $defaultBranch declares $packageName '
      '$defaultBranchVersion, but package port selected latest release tag '
      '$selectedRef ($selectedVersion).';

  @override
  String get nextStep =>
      'Keep using the selected release tag by default. Use --upstream-ref '
      '$defaultBranch only if maintainers explicitly approve targeting the '
      'unreleased default-branch snapshot.';

  @override
  Map<String, Object?> toJson() {
    return {
      'code': 'package.default_branch_version_unreleased',
      'severity': 'warning',
      'message': message,
      'nextStep': nextStep,
      'package': {'name': packageName, 'path': packagePath},
      'selected': {'ref': selectedRef, 'version': selectedVersion},
      'defaultBranch': {
        'branch': defaultBranch,
        'version': defaultBranchVersion,
      },
      'policy': {
        'defaultAction': 'support-selected-release-tag',
        'defaultBranchSnapshotRequiresApproval': true,
      },
    };
  }
}
