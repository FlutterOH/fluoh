import 'package:fluoh/src/schema/schema.dart';
import 'package:test/test.dart';

void main() {
  group('project fluoh.yaml', () {
    test('parses policy and upserts SDK versions', () {
      final config = ProjectFluohConfig.parse('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
dependencyPolicy:
  pubspecSection: dependencies
  versionChanges: any
''');

      expect(config.sdkVersion, '3.35.8-ohos-0.0.3');
      expect(config.dependencyPolicy.pubspecSection.yamlValue, 'dependencies');
      expect(config.dependencyPolicy.versionChanges.yamlValue, 'any');
      expect(
        upsertProjectSdkVersion('''
schema: 1
sdk:
  version: old # keep
''', '4.0.0-ohos-0.0.1'),
        contains('version: 4.0.0-ohos-0.0.1 # keep'),
      );
    });

    test('rejects incomplete SDK versions', () {
      expect(
        () => ProjectFluohConfig.parse('''
schema: 1
sdk:
  version: 3.35.8-ohos
'''),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('pub repository manifest', () {
    test('generates, parses, and derives release rules', () {
      final manifest = createPubRepositoryManifest(
        package: const PubspecPackage(
          name: 'image_gallery_saver',
          version: '2.0.3',
        ),
        upstream: 'https://github.com/fluttercandies/image_gallery_saver',
        packagePath: '.',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: flutterOhosBranchForSdk('3.35.8-ohos-0.0.3'),
        repositoryUrl: 'git@github.com:FlutterOH/image_gallery_saver.git',
      );

      final content = pubRepositoryManifestContent(manifest);
      final parsed = PubRepositoryManifest.parse(content);

      expect(content, contains('name: image_gallery_saver'));
      expect(content, contains('branch: ohos/3.35'));
      expect(content, contains('upstreamVersion: 2.0.3'));
      expect(content, isNot(contains('release:')));
      expect(parsed.branch, 'ohos/3.35');
      expect(parsed.dependencyPath, '.');
      expect(parsed.upstreamPath, '.');
      expect(
        parsed.dependencyUrl,
        'https://github.com/FlutterOH/image_gallery_saver.git',
      );
      expect(parsed.releaseTag, 'image_gallery_saver-2.0.3-ohos-3.35-0.1.0');
    });

    test('rejects legacy ref and release layouts', () {
      expect(
        () => PubRepositoryManifest.parse('''
schema: 1
name: camera
sdk:
  version: 3.35.8-ohos-0.0.3
repository:
  url: git@github.com:FlutterOH/camera.git
  ref: ohos/3.35
upstream:
  url: https://github.com/flutter/packages
packages:
  camera:
    release:
      version: 0.1.0
'''),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid release status and version values', () {
      expect(
        () => PubRepositoryManifest.parse('''
schema: 1
name: camera
sdk:
  version: 3.35.8-ohos-0.0.3
repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35
upstream:
  git:
    url: https://github.com/flutter/packages
packages:
  camera:
    version: canary
    upstreamVersion: "0.11.0"
    status: ready
'''),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects incomplete SDK versions', () {
      expect(
        () => PubRepositoryManifest.parse('''
schema: 1
name: camera
sdk:
  version: 3.35.8-ohos
repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35
upstream:
  git:
    url: https://github.com/flutter/packages
packages:
  camera:
    version: "1"
    upstreamVersion: "0.11.0"
'''),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('source indexes', () {
    test('accepts empty source scaffolds', () {
      final source = parseSourceRootManifest('''
schema: 1
kind: source
name: Empty source
repository:
  git:
    url: file:/tmp/source
''');

      expect(source.sdkReleases, isEmpty);
      expect(source.manifests, isEmpty);
    });

    test('parses SDKs, manifests, and compatible releases', () {
      final sdkIndex = parseSourceSdkIndex('''
schema: 1
kind: source
name: Test source
repository:
  git:
    url: file:/tmp/source
sdk:
  git:
    url: /tmp/flutter-ohos-sdk
  versions:
    - 3.35.8-ohos-0.0.3
manifests:
  - name: camera
''');
      expect(sdkIndex.releases.single.versionSeries, '3.35');

      final manifest = parseSourceManifest(
        label: 'manifests/camera/fluoh.yaml',
        content: '''
schema: 1
kind: manifest
name: camera
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
packages:
  camera:
    repository:
      path: packages/camera
    upstream:
      path: packages/camera
    sdks:
      "3.35":
        releases:
          - version: "1"
            upstreamVersion: "1.0.0"
''',
      );
      final packages = sourcePackageManifestsFromManifest(manifest);

      expect(
        packageIndexFromManifests(
          packages,
        ).packages['camera']!.implementations.single.tag,
        'camera-1.0.0-ohos-3.35-1',
      );
      expect(
        compatibilityMatrixFromManifests(
          packages,
        ).sdkVersions['3.35']!.implemented,
        ['camera'],
      );
    });

    test('quotes generated source scalars when needed', () {
      final content = sourceManifestToContent(
        SourceManifest(
          schemaVersion: 1,
          name: 'camera',
          repositoryGitUrl: 'file:/tmp/camera#adaptation',
          upstreamGitUrl: 'https://github.com/flutter/packages',
          upstreamBranch: 'main',
          packages: const {
            'camera': SourceManifestPackage(
              name: 'camera',
              repositoryPath: 'packages/camera',
              upstreamPath: 'packages/camera',
              maintenance: SourcePackageMaintenance(
                status: 'frozen',
                reason: 'Use upstream: native # available',
              ),
              advisory: SourcePackageAdvisory(
                message: 'Prefer upstream: OHOS # native',
                alternatives: [
                  SourcePackageAlternative(
                    name: 'camera_ohos',
                    reason: 'Native: plugin # maintained',
                    url: 'https://pub.dev/packages/camera_ohos#readme',
                  ),
                ],
              ),
              sdks: {
                '3.35': SourceManifestSdk(
                  sdkLine: '3.35',
                  releases: [
                    SourceManifestRelease(
                      version: '1',
                      upstreamVersion: '1.0.0',
                    ),
                  ],
                ),
              },
            ),
          },
        ),
      );

      final parsed = parseSourceManifest(
        content: content,
        label: 'manifests/camera/fluoh.yaml',
      );

      expect(content, contains('url: "file:/tmp/camera#adaptation"'));
      expect(
        parsed.packages['camera']!.maintenance!.reason,
        'Use upstream: native # available',
      );
      expect(
        parsed.packages['camera']!.advisory!.message,
        'Prefer upstream: OHOS # native',
      );
    });
  });

  group('tool config', () {
    test('round trips source JSON and validates source names', () {
      final config = ToolConfig.fromJson({
        'sources': {
          'private': {
            'path': '/tmp/source',
            'url': 'https://example.com/source.git',
            'priority': 10,
          },
        },
      });

      expect(config.sources['private']!.displayValue, contains('example.com'));
      expect(ToolConfig.fromJson(config.toJson()).sources, contains('private'));
      expect(sourceNameValidationError('../bad'), isNotNull);
      expect(officialSourcePriority, 0);
      expect(defaultSourcePriority, 10);
    });
  });

  group('pubspec and dependency plans', () {
    test('parses dependencies, lockfiles, and dependency chains', () {
      final direct = directDependencyNamesFromPubspec('''
name: app
dependencies:
  flutter:
    sdk: flutter
  camera: ^1.0.0
''');
      final locked = pubLockPackagesFromLock('''
packages:
  camera:
    version: 1.0.0
    dependencies:
      camera_platform_interface: any
  camera_platform_interface:
    version: 1.0.0
sdks:
  dart: ">=3.0.0 <4.0.0"
''');

      expect(direct, {'camera'});
      expect(dependencyChains(locked, direct)['camera_platform_interface'], [
        'camera',
        'camera_platform_interface',
      ]);
    });

    test(
      'selects implementations and rewrites refs without losing comments',
      () {
        const implementation = PackageImplementation(
          sdkLine: '3.35',
          upstreamVersion: '1.1.0',
          repository: 'https://github.com/FlutterOH/camera.git',
          tag: 'camera-1.1.0-ohos-3.35-1',
          version: '1',
          path: 'packages/camera',
        );
        expect(
          bestImplementationForVersion([
            implementation,
            const PackageImplementation(
              sdkLine: '3.35',
              upstreamVersion: '1.0.0',
              repository: 'https://github.com/FlutterOH/camera.git',
              tag: 'camera-1.0.0-ohos-3.35-1',
              version: '1',
            ),
          ], '1.0.0')!.upstreamVersion,
          '1.0.0',
        );

        final result = applyPubspecDependencyChangesToContent(
          content: '''
dependencies:
  camera:
    git:
      url: old
      ref: "camera-1.0.0-ohos-3.35-1" # keep
''',
          changes: [
            const PubspecDependencyChange.updateRef(
              packageName: 'camera',
              implementation: implementation,
              section: PubspecDependencySection.dependencies,
              currentRef: 'camera-1.0.0-ohos-3.35-1',
            ),
          ],
        );

        expect(result.applied, 1);
        expect(
          result.content,
          contains('ref: "camera-1.1.0-ohos-3.35-1" # keep'),
        );
      },
    );

    test('builds dependency plan JSON from a report and pubspec state', () {
      const implementation = PackageImplementation(
        sdkLine: '3.35',
        upstreamVersion: '1.0.0',
        repository: 'https://github.com/FlutterOH/camera.git',
        tag: 'camera-1.0.0-ohos-3.35-1',
        version: '1',
      );
      final plan = buildPubDependencyPlanFromReport(
        report: const PubDependencyReport(
          sdkVersion: '3.35.8-ohos-0.0.3',
          dependencies: [
            DependencyCompatibility(
              name: 'camera',
              version: '1.0.0',
              direct: true,
              status: DependencyStatus.implemented,
              implementation: implementation,
            ),
          ],
        ),
        state: parsePubspecDependencyState('dependencies:\n  camera: ^1.0.0\n'),
        policy: const PubDependencyPolicy(),
        purpose: PubDependencyPlanPurpose.fix,
      );

      expect(
        plan.changes.single.kind,
        PubspecDependencyChangeKind.writeOverride,
      );
      expect(plan.toJson()['pubspecSection'], 'dependency_overrides');
    });
  });
}
