import 'package:fluoh/src/schema/schema.dart';
import 'package:test/test.dart';

void main() {
  group('project fluoh.yaml', () {
    test('parses policy and upserts SDK versions', () {
      final config = ProjectFluohConfig.parse('''
schema: 1
kind: project
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
kind: project
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
kind: project
sdk:
  version: 3.35.8-ohos
dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
'''),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('package repository manifest', () {
    test('generates, parses, and derives release rules', () {
      final manifest = createPackageManifest(
        package: const PubspecPackage(
          name: 'image_gallery_saver',
          version: '2.0.3',
        ),
        upstream: 'https://github.com/fluttercandies/image_gallery_saver',
        packagePath: '.',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: flutterOhosPackageBranchForSdk(
          sdkVersion: '3.35.8-ohos-0.0.3',
          packageName: 'image_gallery_saver',
        ),
        repositoryUrl: 'https://github.com/FlutterOH/image_gallery_saver.git',
        upstreamCommit: '1111111111111111111111111111111111111111',
      );

      final content = packageManifestContent(manifest);
      final parsed = PackageManifest.parse(content);

      expect(content, contains('name: image_gallery_saver'));
      expect(content, contains('kind: package'));
      expect(content, isNot(contains('\nname: image_gallery_saver\n')));
      expect(content, contains('branch: ohos/3.35/image_gallery_saver'));
      expect(content, contains('version: 2.0.3'));
      expect(content, contains('release:'));
      expect(parsed.branch, 'ohos/3.35/image_gallery_saver');
      expect(parsed.package.path, '.');
      expect(
        parsed.dependencyUrl,
        'https://github.com/FlutterOH/image_gallery_saver.git',
      );
      expect(parsed.releaseTag, 'image_gallery_saver-2.0.3-ohos-3.35-0.1.0');
    });

    test('rejects invalid release status and version values', () {
      expect(
        () => PackageManifest.parse('''
schema: 1
kind: package
sdk:
  version: 3.35.8-ohos-0.0.3
repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera
upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main
package:
  name: camera
  path: packages/camera/camera
  release:
    version: canary
    upstream:
      version: "0.11.0"
      commit: "1111111111111111111111111111111111111111"
    status: ready
'''),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unresolved upstream commits', () {
      expect(
        () => PackageManifest.parse('''
schema: 1
kind: package
sdk:
  version: 3.35.8-ohos-0.0.3
repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera
upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main
package:
  name: camera
  path: packages/camera/camera
  release:
    version: "0.1.0"
    upstream:
      version: "0.11.0"
      commit: main
'''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('40-character hexadecimal Git commit hash'),
          ),
        ),
      );
    });

    test('defaults omitted package paths to repository root', () {
      final manifest = PackageManifest.parse('''
schema: 1
kind: package
sdk:
  version: 3.35.8-ohos-0.0.3
repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera
upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main
package:
  name: camera
  release:
    version: "0.1.0"
    upstream:
      version: "0.11.0"
      commit: "1111111111111111111111111111111111111111"
''');

      expect(manifest.package.path, '.');
    });

    test('rejects incomplete SDK versions', () {
      expect(
        () => PackageManifest.parse('''
schema: 1
kind: package
sdk:
  version: 3.35.8-ohos
repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera
upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main
package:
  name: camera
  path: packages/camera/camera
  release:
    version: "1.0.0"
    upstream:
      version: "0.11.0"
      commit: "1111111111111111111111111111111111111111"
'''),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects package branches outside the canonical package format', () {
      final manifest = createPackageManifest(
        package: const PubspecPackage(name: 'camera', version: '0.11.0'),
        upstream: 'https://github.com/flutter/packages',
        packagePath: 'packages/camera/camera',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: 'ohos/3.35',
        repositoryUrl: 'git@github.com:FlutterOH/camera.git',
        upstreamCommit: '1111111111111111111111111111111111111111',
      );

      expect(
        () => packageManifestContent(manifest),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('repository.git.branch must be ohos/3.35/camera'),
          ),
        ),
      );
    });
  });

  group('source indexes', () {
    test('accepts empty source scaffolds', () {
      final source = parseSourceRootManifest('''
schema: 1
kind: source
name: empty-source
''');

      expect(source.sdkReleases, isEmpty);
      expect(source.manifests, isEmpty);
      expect(source.repositoryGitUrl, isNull);
    });

    test('rejects source repository blocks without URLs', () {
      expect(
        () => parseSourceRootManifest('''
schema: 1
kind: source
name: empty-source
repository:
  git: {}
'''),
        throwsA(isA<FormatException>()),
      );
    });

    test('generates source roots without environment constraints', () {
      final content = sourceRootManifestContent(
        const SourceRootManifestTemplate(name: 'test-source'),
      );

      expect(content, isNot(contains('environment:')));
      expect(content, isNot(contains('repository:')));
    });

    test('generates source roots with stable append-friendly ordering', () {
      final content = sourceRootManifestContent(
        const SourceRootManifestTemplate(
          name: 'test-source',
          sdkRepository: 'https://example.com/flutter.git',
          sdkReleases: [
            SdkRelease(
              version: '3.35.10-ohos-0.0.1',
              versionSeries: '3.35',
              flutterVersion: '3.35.10',
              channel: 'stable',
              repository: 'https://example.com/flutter.git',
              tag: '3.35.10-ohos-0.0.1',
            ),
            SdkRelease(
              version: '3.35.9-ohos-0.0.1',
              versionSeries: '3.35',
              flutterVersion: '3.35.9',
              channel: 'stable',
              repository: 'https://example.com/flutter.git',
              tag: '3.35.9-ohos-0.0.1',
            ),
          ],
          manifests: [
            SourceManifestRoute(name: 'webview'),
            SourceManifestRoute(name: 'camera'),
          ],
        ),
      );

      expect(
        content.indexOf('- 3.35.9-ohos-0.0.1'),
        lessThan(content.indexOf('- 3.35.10-ohos-0.0.1')),
      );
      expect(
        content.indexOf('  - name: camera'),
        lessThan(content.indexOf('  - name: webview')),
      );
    });

    test('generates source manifests with oldest releases first', () {
      final content = sourceManifestToContent(
        SourceManifest(
          schemaVersion: 1,
          repositoryGitUrl: 'https://github.com/FlutterOH/camera.git',
          upstreamGitUrl: 'https://github.com/flutter/packages',
          package: const SourceManifestPackage(
            name: 'camera',
            sdks: {
              '3.36': SourceManifestSdk(
                sdkLine: '3.36',
                releases: [
                  SourceManifestRelease(
                    version: '0.1.0',
                    upstreamVersion: '0.9.0',
                    upstreamCommit: '1111111111111111111111111111111111111111',
                  ),
                ],
              ),
              '3.35': SourceManifestSdk(
                sdkLine: '3.35',
                releases: [
                  SourceManifestRelease(
                    version: '0.10.0',
                    upstreamVersion: '0.10.0',
                    upstreamCommit: '2222222222222222222222222222222222222222',
                  ),
                  SourceManifestRelease(
                    version: '0.9.0',
                    upstreamVersion: '0.9.0',
                    upstreamCommit: '3333333333333333333333333333333333333333',
                  ),
                ],
              ),
            },
          ),
        ),
      );

      expect(content.indexOf('"3.35"'), lessThan(content.indexOf('"3.36"')));
      expect(
        content.indexOf('version: 0.9.0'),
        lessThan(content.indexOf('version: 0.10.0')),
      );
    });

    test('rejects unsorted source manifest routes', () {
      expect(
        () => parseSourceRootManifest('''
schema: 1
kind: source
name: test-source
manifests:
  - name: webview
  - name: camera
'''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('manifests must be sorted'),
          ),
        ),
      );
    });

    test('rejects unsorted source manifest SDK lines', () {
      expect(
        () => parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content: '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  sdks:
    "3.36":
      releases:
        - version: "0.1.0"
          upstream:
            version: "1.0.0"
            commit: "1111111111111111111111111111111111111111"
    "3.35":
      releases:
        - version: "0.1.0"
          upstream:
            version: "1.0.0"
            commit: "2222222222222222222222222222222222222222"
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('sdks must be sorted'),
          ),
        ),
      );
    });

    test('rejects unsorted source manifest releases', () {
      expect(
        () => parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content: '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  sdks:
    "3.35":
      releases:
        - version: "0.2.0"
          upstream:
            version: "2.0.0"
            commit: "2222222222222222222222222222222222222222"
        - version: "0.1.0"
          upstream:
            version: "1.0.0"
            commit: "1111111111111111111111111111111111111111"
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('releases must be sorted'),
          ),
        ),
      );
    });

    test('rejects unsafe manifest routes and package paths', () {
      expect(
        () => parseSourceRootManifest('''
schema: 1
kind: source
name: test-source
manifests:
  - name: ../camera
'''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Dart package name'),
          ),
        ),
      );

      expect(
        () => parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content: '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  path: ../camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
            version: "1.0.0"
            ref: camera-v1.0.0
            commit: "1111111111111111111111111111111111111111"
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('normalized relative package path'),
          ),
        ),
      );
    });

    test('rejects explicit source release tags', () {
      expect(
        () => parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content: '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  path: packages/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
            version: "1.0.0"
            ref: camera-v1.0.0
            commit: "2222222222222222222222222222222222222222"
          tag: camera-v1.0.0-ohos-3.35.8-1
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('must not contain "tag"'),
          ),
        ),
      );
    });

    test(
      'rejects source release refs and commits that are not stable tokens',
      () {
        void parseRelease(String upstreamFields) {
          parseSourceManifest(
            label: 'manifests/camera/fluoh.yaml',
            content:
                '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  path: packages/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
$upstreamFields
''',
          );
        }

        expect(
          () => parseRelease(
            '            version: "1.0.0"\n'
            '            ref: "camera v1.0.0"\n'
            '            commit: "1111111111111111111111111111111111111111"\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Git ref without whitespace'),
            ),
          ),
        );
        expect(
          () => parseRelease(
            '            version: "1.0.0"\n'
            '            ref: camera-v1.0.0\n'
            '            commit: main\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('40-character hexadecimal Git commit hash'),
            ),
          ),
        );
      },
    );

    test('parses SDKs, manifests, and compatible releases', () {
      final sdkIndex = parseSourceSdkIndex('''
schema: 1
kind: source
name: test-source
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
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  path: packages/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
            version: "1.0.0"
            ref: camera-v1.0.0
            commit: "1111111111111111111111111111111111111111"
''',
      );
      final packages = sourcePackageManifestsFromManifest(manifest);

      expect(
        packageIndexFromManifests(
          packages,
        ).packages['camera']!.implementations.single.tag,
        'camera-1.0.0-ohos-3.35-1.0.0',
      );
      expect(
        compatibilityMatrixFromManifests(
          packages,
        ).sdkVersions['3.35']!.implemented,
        ['camera'],
      );
    });

    test('requires source release upstream commits', () {
      void parseRelease(String upstreamFields) {
        parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content:
              '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  path: packages/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
$upstreamFields
''',
        );
      }

      expect(
        () => parseRelease(
          '            version: "1.0.0"\n'
          '            ref: camera-v1.0.0\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"commit"'),
          ),
        ),
      );
    });

    test('rejects flat source release upstream fields', () {
      expect(
        () => parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content: '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
package:
  name: camera
  path: packages/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstreamVersion: "1.0.0"
          upstreamRef: camera-v1.0.0
          upstreamCommit: "1111111111111111111111111111111111111111"
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('must not contain "upstreamVersion"'),
          ),
        ),
      );
    });

    test('rejects multi-package source manifests', () {
      expect(
        () => parseSourceManifest(
          label: 'manifests/camera/fluoh.yaml',
          content: '''
schema: 1
kind: manifest
repository:
  git:
    url: /tmp/camera
upstream:
  git:
    url: https://github.com/flutter/packages
packages:
  camera:
    sdks:
      "3.35":
        releases:
          - version: "1.0.0"
            upstream:
              version: "1.0.0"
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('multi-package Source Manifests are no longer supported'),
          ),
        ),
      );
    });

    test('quotes generated source scalars when needed', () {
      final content = sourceManifestToContent(
        SourceManifest(
          schemaVersion: 1,
          repositoryGitUrl: 'file:/tmp/camera#adaptation',
          upstreamGitUrl: 'https://github.com/flutter/packages',
          package: const SourceManifestPackage(
            name: 'camera',
            path: 'packages/camera',
            maintenance: SourcePackageMaintenance(
              frozen: true,
              note: 'Use upstream: native # available',
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
                    version: '1.0.0',
                    upstreamVersion: '1.0.0',
                    upstreamRef: 'camera-v1.0.0',
                    upstreamCommit: '1111111111111111111111111111111111111111',
                  ),
                ],
              ),
            },
          ),
        ),
      );

      final parsed = parseSourceManifest(
        content: content,
        label: 'manifests/camera/fluoh.yaml',
      );

      expect(content, contains('url: "file:/tmp/camera#adaptation"'));
      expect(
        parsed.package.maintenance!.note,
        'Use upstream: native # available',
      );
      expect(
        parsed.package.advisory!.message,
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
          tag: 'camera-1.1.0-ohos-3.35-1.0.0',
          version: '1.0.0',
          path: 'packages/camera',
        );
        expect(
          bestImplementationForVersion([
            implementation,
            const PackageImplementation(
              sdkLine: '3.35',
              upstreamVersion: '1.0.0',
              repository: 'https://github.com/FlutterOH/camera.git',
              tag: 'camera-1.0.0-ohos-3.35-1.0.0',
              version: '1.0.0',
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
      ref: "camera-1.0.0-ohos-3.35-1.0.0" # keep
''',
          changes: [
            const PubspecDependencyChange.updateRef(
              packageName: 'camera',
              implementation: implementation,
              section: PubspecDependencySection.dependencies,
              currentRef: 'camera-1.0.0-ohos-3.35-1.0.0',
            ),
          ],
        );

        expect(result.applied, 1);
        expect(
          result.content,
          contains('ref: "camera-1.1.0-ohos-3.35-1.0.0" # keep'),
        );
      },
    );

    test('builds dependency plan JSON from a report and pubspec state', () {
      const implementation = PackageImplementation(
        sdkLine: '3.35',
        upstreamVersion: '1.0.0',
        repository: 'https://github.com/FlutterOH/camera.git',
        tag: 'camera-1.0.0-ohos-3.35-1.0.0',
        version: '1.0.0',
      );
      final plan = buildDependencyPlanFromReport(
        report: const DependencyReport(
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
        policy: const DependencyPolicy(),
        purpose: DependencyPlanPurpose.fix,
      );

      expect(
        plan.changes.single.kind,
        PubspecDependencyChangeKind.writeOverride,
      );
      expect(plan.toJson()['pubspecSection'], 'dependency_overrides');
    });

    test('parses and rewrites hyphenated package names', () {
      const implementation = PackageImplementation(
        sdkLine: '3.35',
        upstreamVersion: '2.0.0',
        repository: 'https://github.com/FlutterOH/foo-bar.git',
        tag: 'foo-bar-2.0.0-ohos-3.35-1.0.0',
        version: '1.0.0',
      );
      final state = parsePubspecDependencyState('''
dependencies:
  foo-bar: ^2.0.0
dependency_overrides:
  foo-bar:
    git:
      url: https://github.com/FlutterOH/foo-bar.git
      ref: foo-bar-1.0.0-ohos-3.35-1.0.0
''');
      expect(state.overrideNames, contains('foo-bar'));
      expect(
        state.overrideRefs['foo-bar']!.value,
        'foo-bar-1.0.0-ohos-3.35-1.0.0',
      );

      final result = applyPubspecDependencyChangesToContent(
        content: '''
dependencies:
  foo-bar: ^2.0.0
dependency_overrides:
  foo-bar:
    git:
      url: https://github.com/FlutterOH/foo-bar.git
      ref: foo-bar-1.0.0-ohos-3.35-1.0.0
''',
        changes: [
          const PubspecDependencyChange.updateRef(
            packageName: 'foo-bar',
            implementation: implementation,
            section: PubspecDependencySection.dependencyOverrides,
            currentRef: 'foo-bar-1.0.0-ohos-3.35-1.0.0',
          ),
        ],
      );
      expect(result.applied, 1);
      expect(result.content, contains('ref: foo-bar-2.0.0-ohos-3.35-1.0.0'));
    });
  });
}
