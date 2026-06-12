part of 'source_check_command.dart';

class _GitHubPullRequest {
  const _GitHubPullRequest({
    required this.owner,
    required this.repository,
    required this.number,
  });

  final String owner;
  final String repository;
  final String number;

  String get cloneUrl => 'https://github.com/$owner/$repository.git';

  static _GitHubPullRequest? tryParse(String value) {
    final match = RegExp(
      r'^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    return _GitHubPullRequest(
      owner: match.group(1)!,
      repository: match.group(2)!,
      number: match.group(3)!,
    );
  }
}

class _SourceCheckReport {
  const _SourceCheckReport({
    required this.target,
    required this.workRoot,
    required this.sourcePath,
    required this.schemaOnly,
    required this.sourceCheckout,
    required this.sourceValidation,
    required this.baseRef,
    required this.all,
    required this.changedFiles,
    required this.checkedManifests,
    required this.manifests,
    required this.changeSummary,
    required this.releaseCheckPlan,
    required this.releaseChecks,
    required this.sdkChecks,
    required this.warnings,
    required this.errors,
    required this.recommendation,
  });

  final String target;
  final String? workRoot;
  final String sourcePath;
  final bool schemaOnly;
  final _SourceSetupResult sourceCheckout;
  final _SourceValidationCheck sourceValidation;
  final String? baseRef;
  final bool all;
  final List<String> changedFiles;
  final List<String> checkedManifests;
  final List<_CheckedSourceManifest> manifests;
  final _SourceChangeSummary changeSummary;
  final _ReleaseCheckPlan releaseCheckPlan;
  final List<_ManifestReleaseCheck> releaseChecks;
  final List<_SdkReleaseCheck> sdkChecks;
  final List<String> warnings;
  final List<String> errors;
  final String recommendation;

  bool get ok => errors.isEmpty;
  int get exitCode => ok ? 0 : 1;

  Map<String, Object?> toJson() => {
    'recommendation': recommendation,
    'target': target,
    if (workRoot != null) 'workRoot': workRoot,
    'sourcePath': sourcePath,
    'schemaOnly': schemaOnly,
    'sourceCheckout': sourceCheckout.toJson(),
    'sourceValidation': sourceValidation.toJson(),
    if (baseRef != null) 'baseRef': baseRef,
    'all': all,
    'changeType': changeSummary.changeType,
    'changeTypes': changeSummary.changeTypes,
    'affectedManifests': checkedManifests,
    'changedFiles': changedFiles,
    'checkedManifests': checkedManifests,
    'manifests': [for (final manifest in manifests) manifest.toJson()],
    'changedReleaseRecords': [
      for (final check in releaseCheckPlan.changedRecords) check.toJson(),
    ],
    'releaseCheckPlan': releaseCheckPlan.toJson(),
    'skippedReleaseChecks': [
      for (final check in releaseCheckPlan.skipped) check.toJson(),
    ],
    'releaseChecks': [for (final check in releaseChecks) check.toJson()],
    'sdkChecks': [for (final check in sdkChecks) check.toJson()],
    'warnings': warnings,
    'errors': errors,
  };
}

class _SourceSetupResult {
  const _SourceSetupResult({
    required this.kind,
    required this.path,
    required this.ok,
    required this.message,
    this.pullRequest,
    this.clone,
    this.fetch,
    this.checkout,
  });

  factory _SourceSetupResult.local(Directory path) =>
      _SourceSetupResult(kind: 'local', path: path, ok: true, message: 'ok');

  factory _SourceSetupResult.github(
    Directory path,
    _GitHubPullRequest pullRequest, {
    required _ProcessCheckResult clone,
    required _ProcessCheckResult? fetch,
    required _ProcessCheckResult? checkout,
  }) {
    final ok = clone.ok && (fetch?.ok ?? false) && (checkout?.ok ?? false);
    return _SourceSetupResult(
      kind: 'github',
      path: path,
      ok: ok,
      message: checkout?.message ?? fetch?.message ?? clone.message,
      pullRequest: pullRequest,
      clone: clone,
      fetch: fetch,
      checkout: checkout,
    );
  }

  final String kind;
  final Directory path;
  final bool ok;
  final String message;
  final _GitHubPullRequest? pullRequest;
  final _ProcessCheckResult? clone;
  final _ProcessCheckResult? fetch;
  final _ProcessCheckResult? checkout;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'path': path.path,
    'ok': ok,
    'message': message,
    if (pullRequest != null)
      'pullRequest': {
        'owner': pullRequest!.owner,
        'repository': pullRequest!.repository,
        'number': pullRequest!.number,
        'cloneUrl': pullRequest!.cloneUrl,
      },
    if (clone != null) 'clone': clone!.toJson(),
    if (fetch != null) 'fetch': fetch!.toJson(),
    if (checkout != null) 'checkout': checkout!.toJson(),
  };
}

class _SourceValidationCheck {
  const _SourceValidationCheck({
    required this.ok,
    required this.exitCode,
    required this.message,
  });

  final bool ok;
  final int exitCode;
  final String message;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'exitCode': exitCode,
    'message': message,
  };
}

class _ChangedFilesResult {
  const _ChangedFilesResult({
    required this.files,
    required this.warnings,
    required this.checkAllManifests,
  });

  final List<String> files;
  final List<String> warnings;
  final bool checkAllManifests;
}

class _SourceChangeSummary {
  const _SourceChangeSummary(this.changeTypes);

  static const none = _SourceChangeSummary(['none']);

  final List<String> changeTypes;

  String get changeType {
    if (changeTypes.isEmpty) {
      return 'none';
    }
    if (changeTypes.length == 1) {
      return changeTypes.single;
    }
    return 'mixed';
  }
}

class _CheckedSourceManifest {
  const _CheckedSourceManifest({
    required this.routeName,
    required this.manifest,
  });

  final String routeName;
  final SourceManifest manifest;

  Map<String, Object?> toJson() => {
    'routeName': routeName,
    'name': manifest.name,
    'repository': manifest.repositoryGitUrl,
    'packagePath': manifest.package.path,
    'upstream': manifest.upstreamGitUrl,
    'package': {
      'name': manifest.package.name,
      'path': manifest.package.path,
      'sdks': [
        for (final sdk in manifest.package.sdks.values)
          {
            'sdkLine': sdk.sdkLine,
            'releases': [
              for (final release in sdk.releases)
                {
                  'version': release.version,
                  'upstreamVersion': release.upstreamVersion,
                  if (release.upstreamRef != null)
                    'upstreamRef': release.upstreamRef,
                  'upstreamCommit': release.upstreamCommit,
                  'status': release.status,
                },
            ],
          },
      ],
    },
  };
}

class _SdkReleaseCheck {
  const _SdkReleaseCheck({
    required this.version,
    required this.tag,
    required this.repository,
    required this.resolvedRepository,
    required this.reason,
    required this.result,
    required this.ok,
  });

  final String version;
  final String tag;
  final String repository;
  final String resolvedRepository;
  final String reason;
  final _ProcessCheckResult result;
  final bool ok;

  String get message => result.ok && result.stdout.trim().isEmpty
      ? 'Tag $tag was not found in $repository.'
      : result.message;

  Map<String, Object?> toJson() => {
    'version': version,
    'tag': tag,
    'repository': repository,
    'resolvedRepository': resolvedRepository,
    'reason': reason,
    'ok': ok,
    'tagCheck': result.toJson(),
  };
}

class _ReleaseCheckPlan {
  const _ReleaseCheckPlan({
    required this.items,
    required this.skipped,
    required this.warnings,
  });

  static const empty = _ReleaseCheckPlan(items: [], skipped: [], warnings: []);

  final List<_PlannedReleaseCheck> items;
  final List<_SkippedReleaseCheck> skipped;
  final List<String> warnings;

  List<_PlannedReleaseCheck> get changedRecords => [
    ...items,
    for (final skippedCheck in skipped) skippedCheck.check,
  ];

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'skipped': [for (final item in skipped) item.toJson()],
    'warnings': warnings,
  };
}

class _ReleaseManifestDiff {
  const _ReleaseManifestDiff({required this.items, required this.skipped});

  final List<_PlannedReleaseCheck> items;
  final List<_SkippedReleaseCheck> skipped;
}

class _ReleaseCheckShard {
  const _ReleaseCheckShard({required this.index, required this.total});

  final int index;
  final int total;
}

class _PlannedReleaseCheck {
  const _PlannedReleaseCheck({
    required this.manifestName,
    required this.package,
    required this.sdk,
    required this.release,
    required this.tag,
    required this.reason,
  });

  final String manifestName;
  final SourceManifestPackage package;
  final SourceManifestSdk sdk;
  final SourceManifestRelease release;
  final String tag;
  final String reason;

  Map<String, Object?> toJson() => {
    'manifest': manifestName,
    'package': package.name,
    'sdkLine': sdk.sdkLine,
    'version': release.version,
    'upstreamVersion': release.upstreamVersion,
    'upstreamRef': release.upstreamRef,
    'upstreamCommit': release.upstreamCommit,
    'status': release.status,
    'tag': tag,
    'reason': reason,
  };
}

class _SkippedReleaseCheck {
  const _SkippedReleaseCheck({required this.check, required this.skipReason});

  final _PlannedReleaseCheck check;
  final String skipReason;

  Map<String, Object?> toJson() => {
    ...check.toJson(),
    'skipReason': skipReason,
  };
}

class _TaggedPackageMetadataCheck {
  const _TaggedPackageMetadataCheck({
    required this.ok,
    required this.message,
    required this.branch,
    required this.packageManifest,
    required this.packageName,
    required this.show,
    this.package,
  });

  final bool ok;
  final String message;
  final String? branch;
  final PackageManifest? packageManifest;
  final String packageName;
  final PackageManifestPackage? package;
  final _ProcessCheckResult show;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'message': message,
    'package': packageName,
    if (branch != null) 'branch': branch,
    if (packageManifest != null) ...{
      'sdkVersion': packageManifest!.sdkVersion,
      'repositoryBranch': packageManifest!.repositoryBranch,
    },
    if (package != null) ...{
      'version': package!.version,
      'upstreamVersion': package!.upstreamVersion,
      if (package!.upstreamRef != null) 'upstreamRef': package!.upstreamRef,
      'upstreamCommit': package!.upstreamCommit,
      'status': package!.status ?? 'compatible',
      'packagePath': package!.path,
    },
    'show': show.toJson(),
  };
}

class _ReleaseVerificationResult {
  const _ReleaseVerificationResult({
    required this.items,
    required this.warnings,
  });

  final List<_ManifestReleaseCheck> items;
  final List<String> warnings;
}

class _ManifestReleaseCheck {
  const _ManifestReleaseCheck({
    required this.manifestName,
    required this.repository,
    required this.checks,
  });

  final String manifestName;
  final _PackageRepositoryCheck repository;
  final List<_PackageReleaseCheck> checks;

  Map<String, Object?> toJson() => {
    'manifest': manifestName,
    'ok': repository.ok && checks.every((check) => check.ok),
    'repository': repository.toJson(),
    'checks': [for (final check in checks) check.toJson()],
  };
}

class _PackageRepositoryCheck {
  const _PackageRepositoryCheck({
    required this.ok,
    required this.repository,
    required this.resolvedRepository,
    required this.path,
    required this.clone,
    required this.fetchTags,
  });

  final bool ok;
  final String repository;
  final String resolvedRepository;
  final String path;
  final _ProcessCheckResult clone;
  final _ProcessCheckResult? fetchTags;

  String get message => fetchTags?.message ?? clone.message;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'repository': repository,
    'resolvedRepository': resolvedRepository,
    'path': path,
    'clone': clone.toJson(),
    if (fetchTags != null) 'fetchTags': fetchTags!.toJson(),
  };
}

class _PackageReleaseCheck {
  const _PackageReleaseCheck({
    required this.packageName,
    required this.sdkLine,
    required this.releaseVersion,
    required this.upstreamVersion,
    required this.status,
    required this.tag,
    required this.branch,
    required this.tagCheck,
    required this.metadataCheck,
    required this.checkout,
    required this.packageCheck,
    required this.packageCheckJson,
    required this.ok,
  });

  final String packageName;
  final String sdkLine;
  final String releaseVersion;
  final String upstreamVersion;
  final String status;
  final String tag;
  final String? branch;
  final _ProcessCheckResult tagCheck;
  final _TaggedPackageMetadataCheck? metadataCheck;
  final _ProcessCheckResult? checkout;
  final _ProcessCheckResult? packageCheck;
  final Map<String, Object?>? packageCheckJson;
  final bool ok;

  String get message {
    if (!tagCheck.ok) {
      return tagCheck.message;
    }
    if (metadataCheck != null && !metadataCheck!.ok) {
      return metadataCheck!.message;
    }
    if (checkout != null && !checkout!.ok) {
      return checkout!.message;
    }
    if (packageCheck != null && !packageCheck!.ok) {
      return packageCheck!.message;
    }
    return packageCheck?.message ??
        checkout?.message ??
        metadataCheck?.message ??
        tagCheck.message;
  }

  Map<String, Object?> toJson() => {
    'package': packageName,
    'sdkLine': sdkLine,
    'version': releaseVersion,
    'upstreamVersion': upstreamVersion,
    'status': status,
    'tag': tag,
    if (branch != null) 'branch': branch,
    'ok': ok,
    'tagCheck': tagCheck.toJson(),
    if (metadataCheck != null) 'metadataCheck': metadataCheck!.toJson(),
    if (checkout != null) 'checkout': checkout!.toJson(),
    if (packageCheck != null) 'packageCheck': packageCheck!.toJson(),
    if (packageCheckJson != null) 'packageCheckJson': packageCheckJson,
  };
}

class _ProcessCheckResult {
  const _ProcessCheckResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final List<String> command;
  final int? exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
  String get message => stderr.isNotEmpty ? stderr : stdout;

  Map<String, Object?> toJson() => {
    'command': command,
    'ok': ok,
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
  };
}
