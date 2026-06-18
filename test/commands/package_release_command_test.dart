import 'dart:io';
import 'dart:convert';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

part 'package_release_core_part.dart';
part 'package_release_certification_part.dart';
part 'package_release_validation_part.dart';
part 'package_release_metadata_part.dart';

void main() {
  _registerPackageReleaseCoreTests();
  _registerPackageReleaseCertificationTests();
  _registerPackageReleaseValidationTests();
  _registerPackageReleaseMetadataTests();
}

Future<File> _writeCertificationReport(
  Directory packageRepository, {
  bool includeOhosRun = false,
  int ohosBuildExit = 0,
  String ohosBuildResult = 'passed',
  String recommendation = 'ready',
}) async {
  final reportDirectory = Directory(
    '${packageRepository.path}/.fluoh/tasks/camera-support/reports',
  );
  await reportDirectory.create(recursive: true);
  final report = File('${reportDirectory.path}/report-1780401600123.md');
  final ohosRunRow = includeOhosRun
      ? '| `fluoh run ohos --package camera --json` | 0 | passed | installed, launched, collected hilog, and captured post-launch screenshot .fluoh/tasks/camera-support/evidence/screenshots/camera-ohos-main.png |\n'
      : '';
  await report.writeAsString('''
# fluoh AI Report

- Scope: camera
- Repository: package_release
- Package: camera
- Upstream version: 0.11.0
- FlutterOH SDK: 3.35.8-ohos-0.0.3
- Date: 2026-06-02
- Recommendation: $recommendation

## Summary

- camera is certified for release.

## Changes

- Added OHOS package support evidence.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Existing-platform regression risk: no existing Android, iOS, macOS, Linux, Web, or Windows example platform in fixture

## Official Platform Basis

| Topic | Source | Decision / impact |
| --- | --- | --- |
| OpenHarmony Flutter platform plugin and package behavior | OpenHarmony official API reference | no additional device-side platform API required for this fixture |

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package camera --json` | 0 | passed | package and example baseline passed |
| `fluoh build ohos --package camera --auto-sign --json` | $ohosBuildExit | $ohosBuildResult | signed HAP was produced |
| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed; post-launch screenshot .fluoh/tasks/camera-support/evidence/screenshots/camera-ohos-main.png captured |
$ohosRunRow
## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.
- [x] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [x] Official platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [x] Target-platform build evidence recorded, including OHOS when in scope.
- [x] Target-platform run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Pub.dev publishability checked with `dart pub publish --dry-run`, or a concrete not-applicable reason is recorded.
- [x] FlutterOH support checked with fluoh verify/build/run/drive/report gates.
- [x] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [x] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.
- [x] Interaction automation evidence recorded through a passed `flutter test integration_test -d <device>` command or real `fluoh drive --json`, with no unresolved ready-blocking gates.
- [x] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [x] Public API, dependency constraints, and existing-platform regression risk reviewed.
- [x] Remaining risks and release decision are explicit.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | ${includeOhosRun ? 'passed' : 'skipped with blocker'} | not required | ${includeOhosRun ? 'emulator' : 'none'} | build evidence recorded; post-launch UI-state evidence recorded when automation ran |
| Android | not present | not present | not required | none | no Android example platform |
| iOS | not present | not present | not required | none | no iOS example platform |
| macOS | not present | not present | not required | none | no macOS example platform |

## Automation Coverage

- coveragePolicy.status: readyForExecution
- readyForAutomation: true
- qualityGateSummary: ready=10, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | package API and example inventory reviewed |
| coverage-metadata | readyForReview | every scenario has coverage metadata or no interaction is required |
| coverage-items | readyForReview | all applicable capability rows reviewed |
| capability-inventory-coverage | readyForReview | all package capabilities covered or explicitly notApplicable |
| blocked-coverage | readyForReview | no blocked rows remain |
| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |
| page-readiness | readyForReview | post-launch functional page state asserted or no launch scenario required |
| existing-test-baseline | readyForReview | package tests present for fixture library |
| manifest-permission-coverage | readyForReview | no selected-platform manifest runtime permissions apply |
| behavior-paths | readyForReview | no device-side behavior path applies to fixture |

## Interaction Evidence

No interaction required: fixture package has no device-side interaction flow.

## Diagnostics

- No diagnostics remain.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: automatic debug signing
- Generated HAPs: camera-ohos-debug.hap
- Hilog: no crash marker detected

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: .fluoh/tasks/camera-support/reports/report-1780401600123.md
- Files that must not be committed: local AI reports and device logs

## Release Decision

Release recommendation: $recommendation

Reason: baseline and OHOS evidence are complete.
''');
  return report;
}

String _replaceReportSection(
  String content,
  String heading,
  String replacementBody,
) {
  final pattern = RegExp(
    '^${RegExp.escape(heading)}\\s*\\n[\\s\\S]*?(?=^##\\s|\\z)',
    multiLine: true,
  );
  return content.replaceFirstMapped(pattern, (_) {
    final body = replacementBody.trimRight();
    if (body.isEmpty) {
      return '$heading\n\n';
    }
    return '$heading\n\n$body\n\n';
  });
}
