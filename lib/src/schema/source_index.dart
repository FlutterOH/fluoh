import 'dependency_policy.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

part 'source_index_parsers.dart';
part 'source_index_writers.dart';
part 'source_index_builders.dart';
part 'source_index_readers.dart';
part 'source_index_sorting.dart';

/// Current schema version for Source root and Manifest YAML files.
const sourceManifestSchema = 1;

/// Parsed root `fluoh.yaml` for a FlutterOH Source repository.
///
/// A Source repository owns SDK releases and routes to package Manifest files.
class SourceRootManifest {
  /// Creates parsed Source root manifest data.
  const SourceRootManifest({
    required this.schemaVersion,
    required this.name,
    required this.manifests,
    required this.sdkRepository,
    required this.sdkReleases,
    this.description,
    this.repositoryGitUrl,
  });

  /// Schema version from the root `fluoh.yaml`.
  final int schemaVersion;

  /// Source name, such as `flutteroh`.
  final String name;

  /// Optional human-readable Source description.
  final String? description;

  /// Git URL for the Source repository itself.
  final String? repositoryGitUrl;

  /// Manifest routes registered by this Source.
  final List<SourceManifestRoute> manifests;

  /// Git repository that contains FlutterOH SDK releases.
  final String? sdkRepository;

  /// SDK releases advertised by this Source.
  final List<SdkRelease> sdkReleases;

  /// SDK-only view of this Source.
  SdkIndex get sdkIndex =>
      SdkIndex(schemaVersion: schemaVersion, releases: sdkReleases);
}

/// Data used to generate a Source root `fluoh.yaml` template.
class SourceRootManifestTemplate {
  /// Creates data for a Source root manifest template.
  const SourceRootManifestTemplate({
    required this.name,
    this.description,
    this.repositoryGitUrl,
    this.manifests = const <SourceManifestRoute>[],
    this.sdkRepository,
    this.sdkReleases = const <SdkRelease>[],
  });

  /// Source name written to the generated root manifest.
  final String name;

  /// Optional human-readable Source description.
  final String? description;

  /// Optional Git URL for the Source repository itself.
  final String? repositoryGitUrl;

  /// Package Manifest routes written under `manifests`.
  final List<SourceManifestRoute> manifests;

  /// Optional SDK repository URL written under `sdk.git.url`.
  final String? sdkRepository;

  /// SDK releases listed in the generated root manifest.
  final List<SdkRelease> sdkReleases;
}

/// Route from a Source root to one package Manifest file.
class SourceManifestRoute {
  /// Creates a route to `manifests/<name>/fluoh.yaml`.
  const SourceManifestRoute({required this.name});

  /// Manifest route name.
  final String name;
}

/// Parsed SDK release index.
class SdkIndex {
  /// Creates an SDK release index.
  const SdkIndex({required this.schemaVersion, required this.releases});

  /// Schema version used by the source data.
  final int schemaVersion;

  /// SDK releases sorted and merged from configured Sources.
  final List<SdkRelease> releases;
}

/// Public name for SDK index data used by source APIs.
typedef SourceSdkIndex = SdkIndex;

/// FlutterOH SDK release advertised by Source data.
class SdkRelease {
  /// Creates an SDK release record.
  const SdkRelease({
    required this.version,
    required this.versionSeries,
    required this.flutterVersion,
    required this.channel,
    required this.repository,
    required this.tag,
    this.publishedAt,
    this.sourceName,
    this.sourcePriority = 0,
  });

  /// FlutterOH SDK package version.
  final String version;

  /// Version line, such as `3.35`.
  final String versionSeries;

  /// Upstream Flutter version this SDK line is based on.
  final String flutterVersion;

  /// Release channel, such as `stable`.
  final String channel;

  /// Git repository containing the SDK source.
  final String repository;

  /// Git tag used to install this SDK.
  final String tag;

  /// Optional publish timestamp from Source metadata.
  final String? publishedAt;

  /// Source name that provided this release after merge.
  final String? sourceName;

  /// Source priority used to resolve overlapping releases.
  final int sourcePriority;

  /// Returns a copy annotated with Source merge metadata.
  SdkRelease withSource(String name, int priority) {
    return SdkRelease(
      version: version,
      versionSeries: versionSeries,
      flutterVersion: flutterVersion,
      channel: channel,
      repository: repository,
      tag: tag,
      publishedAt: publishedAt,
      sourceName: name,
      sourcePriority: priority,
    );
  }
}

/// Parsed package Manifest file from `manifests/<name>/fluoh.yaml`.
class SourceManifest {
  /// Creates parsed Source package Manifest data.
  const SourceManifest({
    required this.schemaVersion,
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.package,
  });

  /// Schema version from the Manifest file.
  final int schemaVersion;

  /// Manifest name, derived from the package name.
  String get name => package.name;

  /// FlutterOH implementation repository URL.
  final String repositoryGitUrl;

  /// Upstream repository URL.
  final String upstreamGitUrl;

  /// Package record described by this Manifest.
  final SourceManifestPackage package;
}

/// Package entry inside a Source Manifest.
class SourceManifestPackage {
  /// Creates a package entry from a Source Manifest.
  const SourceManifestPackage({
    required this.name,
    required this.sdks,
    String? path,
    this.maintenance,
    this.advisory,
  }) : path = path ?? '.';

  /// Package name.
  final String name;

  /// Package path inside both the FlutterOH implementation and upstream repositories.
  final String path;

  /// Optional maintenance status for this package.
  final SourcePackageMaintenance? maintenance;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;

  /// SDK-specific release records keyed by SDK line.
  final Map<String, SourceManifestSdk> sdks;
}

/// Manifest releases for one SDK line.
class SourceManifestSdk {
  /// Creates SDK-line release data from a Source Manifest.
  const SourceManifestSdk({required this.sdkLine, required this.releases});

  /// SDK line, such as `3.35`.
  final String sdkLine;

  /// Package implementation releases for this SDK line.
  final List<SourceManifestRelease> releases;
}

/// One package implementation release in a Source Manifest.
class SourceManifestRelease {
  /// Creates one package implementation release record.
  const SourceManifestRelease({
    required this.version,
    required this.upstreamVersion,
    required this.upstreamCommit,
    this.upstreamRef,
    this.status = 'compatible',
  });

  /// FlutterOH package version.
  final String version;

  /// Upstream package version this implementation targets.
  final String upstreamVersion;

  /// Upstream release tag or ref used for the adaptation.
  final String? upstreamRef;

  /// Resolved upstream commit used for the adaptation.
  final String upstreamCommit;

  /// Compatibility status; consumers use `compatible` releases by default and
  /// may explicitly opt into every status through project policy.
  final String status;
}

/// Maintainer-provided package maintenance state.
class SourcePackageMaintenance {
  /// Creates package maintenance status metadata.
  const SourcePackageMaintenance({this.frozen = false, this.note});

  /// Whether source sync should skip generated release updates.
  final bool frozen;

  /// Optional explanation for the maintenance state.
  final String? note;
}

/// Advisory shown when a package needs user or maintainer attention.
class SourcePackageAdvisory {
  /// Creates advisory metadata for a package.
  const SourcePackageAdvisory({
    this.message,
    this.alternatives = const <SourcePackageAlternative>[],
  });

  /// Human-readable advisory message.
  final String? message;

  /// Suggested alternative packages.
  final List<SourcePackageAlternative> alternatives;

  /// Converts this advisory to JSON for command output.
  Map<String, Object?> toJson() {
    return {
      if (message != null) 'message': message,
      if (alternatives.isNotEmpty)
        'alternatives': [
          for (final alternative in alternatives) alternative.toJson(),
        ],
    };
  }
}

/// Alternative package suggested by a Source advisory.
class SourcePackageAlternative {
  /// Creates one advisory alternative package.
  const SourcePackageAlternative({required this.name, this.reason, this.url});

  /// Alternative package name.
  final String name;

  /// Optional reason why this package is suggested.
  final String? reason;

  /// Optional URL for the alternative.
  final String? url;

  /// Converts this alternative to JSON for command output.
  Map<String, Object?> toJson() {
    return {
      'name': name,
      if (reason != null) 'reason': reason,
      if (url != null) 'url': url,
    };
  }
}

/// Data used to generate a package Manifest template.
class SourceManifestTemplate {
  /// Creates data for a Source package Manifest template.
  const SourceManifestTemplate({
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.package,
  });

  /// Manifest name, derived from the package name.
  String get name => package.name;

  /// FlutterOH implementation repository URL.
  final String repositoryGitUrl;

  /// Upstream repository URL.
  final String upstreamGitUrl;

  /// Package entry to generate.
  final SourceManifestPackageTemplate package;
}

/// Data used to generate one package entry in a Manifest template.
class SourceManifestPackageTemplate {
  /// Creates a package entry for a Source Manifest template.
  const SourceManifestPackageTemplate({
    required this.name,
    required this.upstreamVersion,
    required this.sdkLine,
    required this.version,
    required this.upstreamCommit,
    this.path = '.',
    this.upstreamRef,
    this.status = 'compatible',
  });

  /// Package name.
  final String name;

  /// Package path inside both the FlutterOH implementation and upstream repositories.
  final String path;

  /// Upstream version targeted by the generated implementation release.
  final String upstreamVersion;

  /// Upstream release tag or ref used for the generated release.
  final String? upstreamRef;

  /// Resolved upstream commit used for the generated release.
  final String upstreamCommit;

  /// SDK line for the generated implementation release.
  final String sdkLine;

  /// FlutterOH package version for the generated implementation release.
  final String version;

  /// Compatibility status written to the Manifest.
  final String status;
}

/// Merged package index consumed by dependency commands.
class PackageIndex {
  /// Creates a merged package index.
  const PackageIndex({required this.schemaVersion, required this.packages});

  /// Schema version used by the source data.
  final int schemaVersion;

  /// Package entries keyed by package name.
  final Map<String, PackageEntry> packages;
}

/// Package-level Source record after merging configured Sources.
class PackageEntry {
  /// Creates one merged package index entry.
  const PackageEntry({
    required this.repository,
    required this.upstream,
    required this.implementations,
    this.compatibility = const <SourceCompatibilityStatus>[],
    this.sourceNames = const <String>[],
    this.advisory,
    this.maintenance,
  });

  /// FlutterOH implementation repository URL.
  final String repository;

  /// Upstream repository URL.
  final String upstream;

  /// Compatible implementation releases for this package.
  final List<PackageImplementation> implementations;

  /// Non-compatible release records used for reporting.
  final List<SourceCompatibilityStatus> compatibility;

  /// Configured Source aliases that contributed this package entry.
  final List<String> sourceNames;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;

  /// Optional maintenance state for this package.
  final SourcePackageMaintenance? maintenance;
}

/// Concrete FlutterOH implementation release for a package.
class PackageImplementation {
  /// Creates a concrete FlutterOH package implementation record.
  const PackageImplementation({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.repository,
    required this.tag,
    required this.version,
    this.path,
    this.sourceName,
    this.sourcePriority = 0,
    this.status = 'compatible',
  });

  /// SDK line this implementation supports.
  final String sdkLine;

  /// Upstream package version this implementation targets.
  final String upstreamVersion;

  /// Implementation repository URL.
  final String repository;

  /// Implementation repository tag.
  final String tag;

  /// FlutterOH package version.
  final String version;

  /// Package path inside the implementation repository.
  final String? path;

  /// Source release status that produced this implementation.
  final String status;

  /// Source name that provided this implementation after merge.
  final String? sourceName;

  /// Source priority used to resolve overlapping implementation records.
  final int sourcePriority;

  /// SDK version selector used by command code.
  String get sdkVersion => sdkLine;

  /// Returns a copy annotated with Source merge metadata.
  PackageImplementation withSource(String name, int priority) {
    return PackageImplementation(
      sdkLine: sdkLine,
      upstreamVersion: upstreamVersion,
      repository: repository,
      tag: tag,
      version: version,
      path: path,
      sourceName: name,
      sourcePriority: priority,
      status: status,
    );
  }
}

/// Non-compatible package status used for diagnostics.
class SourceCompatibilityStatus {
  /// Creates one non-compatible package status record.
  const SourceCompatibilityStatus({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.status,
  });

  /// SDK line this status applies to.
  final String sdkLine;

  /// Upstream package version this status applies to.
  final String upstreamVersion;

  /// Status such as `experimental` or `broken`.
  final String status;

  /// SDK version selector used by command code.
  String get sdkVersion => sdkLine;
}

/// Package-specific view derived from one Source Manifest.
class SourcePackageManifest {
  /// Creates a package-specific view of Source Manifest data.
  const SourcePackageManifest({
    required this.name,
    required this.repository,
    required this.upstream,
    required this.implementations,
    required this.compatibility,
    this.maintenance,
    this.advisory,
  });

  /// Package name.
  final String name;

  /// FlutterOH implementation repository URL.
  final String repository;

  /// Upstream repository URL.
  final String upstream;

  /// Compatible implementation releases.
  final List<PackageImplementation> implementations;

  /// Non-compatible release records used for reporting.
  final List<SourceCompatibilityStatus> compatibility;

  /// Optional maintenance state for this package.
  final SourcePackageMaintenance? maintenance;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;
}

/// Compatibility buckets derived from Source manifests.
class CompatibilityMatrix {
  /// Creates compatibility matrix data.
  const CompatibilityMatrix({
    required this.schemaVersion,
    required this.sdkVersions,
  });

  /// Schema version for the matrix data.
  final int schemaVersion;

  /// Compatibility data keyed by SDK version.
  final Map<String, CompatibilityVersion> sdkVersions;
}

/// Package compatibility buckets for one SDK version.
class CompatibilityVersion {
  /// Creates compatibility buckets for one SDK version.
  const CompatibilityVersion({
    required this.native,
    required this.implemented,
    required this.blocked,
  });

  /// Packages with native upstream support.
  final List<String> native;

  /// Packages with FlutterOH implementations.
  final List<String> implemented;

  /// Packages that are known blockers.
  final List<String> blocked;
}
