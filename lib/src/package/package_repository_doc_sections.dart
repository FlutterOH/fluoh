part of 'package_repository_docs.dart';

List<String> _localCommitCheckpointLines({
  required bool multiPackage,
  String? packageScope,
}) {
  final packageCommitScope = packageScope ?? '<name>';
  final commitScopeGuidance = multiPackage
      ? '- Use Conventional Commits with the package name as the scope for package-specific changes, such as `feat($packageCommitScope): add OHOS platform scaffold` or `test($packageCommitScope): cover OHOS channel calls`. Use repository-level scopes such as `docs`, `ci`, or `release` only for changes that are not specific to one package.'
      : '- Use Conventional Commits without a package-name scope when the current branch adapts only this package, such as `feat: add OHOS platform scaffold` or `test: cover OHOS channel calls`. Use a scope only when it adds real context, such as `docs`, `ci`, `example`, or `release`.';
  return [
    '## Local Commit Checkpoints',
    '',
    '- The approved adaptation scope authorizes small local checkpoint commits during the AI workflow.',
    '- Before adaptation commits, resolve the repository URL/path recorded in `repository.git.url` and the local Git author identity that will be used for commits.',
    '- Create small local commits at completed checkpoints instead of one large final commit, such as generated baseline, selected-SDK baseline, implementation, tests and example verification, release metadata, and delivery report handoff.',
    '- Keep commits local unless the maintainer explicitly asks you to push.',
    '- Before the first commit, run `git config --local --get user.name` and `git config --local --get user.email`; if either is missing or contradicts the resolved identity, ask for author info, then set `git config --local user.name <name>` and `git config --local user.email <email>`. New package repositories can also be created with `fluoh package create <upstream> --repository-name <repository-name> --git-author-name <name> --git-author-email <email>`.',
    '- Stage explicit paths for each checkpoint and review `git diff --cached` before committing.',
    '- Run the checkpoint\'s relevant verification command and `git diff --check` before each commit.',
    '- Keep `.fluoh` reports/traces, caches, credentials, signing secrets, generated local build output, and machine-local paths out of commits.',
    commitScopeGuidance,
    '- Do not commit failing work unless the maintainer explicitly requests a local WIP checkpoint.',
    '',
  ];
}

List<String> _adaptationGuardrailLines() {
  return [
    '## Guardrails',
    '',
    '- Ask before changing Dart public APIs, package names, dependency constraints, non-default release version policy, manual release version overrides, repository remotes, or branch layout. Normal package version/status metadata updates in this workflow do not need separate confirmation.',
    '- Ask before deleting upstream files, replacing platform implementations wholesale, force-pushing, running destructive Git commands, or committing failing work.',
    '- Do not invent OHOS APIs, permissions, manifest fields, or signing values. Derive them from upstream platform behavior, generated errors, or existing FlutterOH package implementations; stop and ask when the source is unclear.',
    '- Preserve the local worktree on network, GitHub, push, sync, or release failures; summarize the failure and leave retryable next steps.',
    '',
  ];
}

List<String> _multiAdaptationCommandFlowLines() {
  return [
    '## Automatic Adaptation Command Flow',
    '',
    'Use this command flow as the primary loop. The detailed workflow and platform matrix below add context, but these commands decide when to edit, when to fix local environment, and when the work can be handed back.',
    '',
    '1. Repository setup: use `fluoh package create <upstream> --repository-name <repository-name>` to create the first package branch, `fluoh package queue <package-path>... --json` to resolve a read-only multi-package queue, `fluoh package add <package-path> --plan --json` to inspect one additional branch before writing, `fluoh package add <package-path>` to create another package branch from that package release, and `fluoh package sync` only after a completed clean checkpoint when an upstream package release needs to be merged. Omitted upstream targets resolve to the latest valid package release tag; use `--upstream-version <version>` only when adapting a specific same-or-newer upstream version. `fluoh package sync` refuses upstream downgrades; mark the current adaptation `broken` with `fluoh package version --status broken` instead. For whole-repository work, finish one package branch checkpoint sequence before moving to the next package. When verifying multiple existing package branches, prefer a fresh clone or separate Git worktree per package branch so ignored platform build artifacts from one branch cannot become untracked files on another branch. Do not run destructive cleanup commands such as `git clean` without explicit maintainer approval.',
    '2. Baseline gates: run `fluoh deps get`, `fluoh doctor --project --json --strict`, `fluoh flutter analyze`, and existing package or example tests before adding OHOS code. Project warnings mean repository fixes; environment warnings mean local toolchain or Source fixes.',
    '3. Implementation loop: after code, dependency, SDK, or metadata changes, rerun `fluoh deps get` when needed, then `fluoh verify --package <name> --json --trace-dir <trace-dir>` until pub get, analysis, and existing tests pass.',
    '4. OHOS loop: run `fluoh run ohos --package <name> --auto-emulator --json --trace-dir <trace-dir>`, or add `--device-id <id>` for a connected OHOS target. This prepares debug signing, launches through `flutter run`, captures run/session evidence, and executes `example/integration_test/` on the selected target when present. If no local target can be started, run `fluoh build ohos --package <name> --auto-sign --json --trace-dir <trace-dir>` as build-only evidence and record the environment blocker.',
    '5. Existing-platform loop: for Android, run `fluoh doctor --platform android --json --strict`, then `fluoh run android --package <name> --auto-emulator --json` when `example/android` exists. For iOS, run `fluoh doctor --platform ios --json --strict`, then `fluoh run ios --package <name> --auto-emulator --json` when `example/ios` exists. For macOS, run `fluoh doctor --platform macos --json --strict`, then `fluoh run macos --package <name> --json` when `example/macos` exists. For Web, run `fluoh doctor --platform web --json --strict`, then `fluoh run web --package <name> --json` when `example/web` exists. For Linux and Windows, run the matching doctor command and `fluoh build linux|windows --package <name> --json` when those example directories exist. Add or run `integration_test/` for tappable workflows; otherwise run an AI-assisted interaction scenario or manual-assisted fallback and record the reviewer, target, result, blocker, and tool-readable evidence beyond launch-only session state.',
    '6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`, `stderrTail`, saved logs, verify `dirtyAfterVerify`/`workingTreeChanges`, trace manifest `result`, and trace `feedbackCandidates` before editing. Fix `doctor` failures in local tooling, project warnings in repository configuration, unexpected generated-file changes, and verification failures in the package or example that produced the diagnostic.',
    '7. Implementation checkpoint: once implementation, OHOS evidence, and applicable existing-platform regression checks are clean or explicitly blocked, create a local implementation checkpoint commit. This clean worktree is required before `fluoh package version`, `fluoh package sync`, and `fluoh package check`.',
    '8. Release metadata checkpoint: run `fluoh package status --package <name>`, update release metadata with `fluoh package version --package <name>` when needed, update `FLUOH_CHANGELOG.md`, review `fluoh.yaml`, then create a local release metadata checkpoint commit. `fluoh package version` requires a clean worktree before it writes metadata.',
    '9. Final report and release gate: rerun final `fluoh verify --package <name>`, create `.fluoh/reports/<name>/report-<timestamp>.md` with command results, platform matrix, automation coverage gates, interaction evidence, diagnostics, Fluoh Feedback entries from trace manifests or an explicit `No fluoh feedback: <reason>` statement, signing mode, logs, risks, and release recommendation, create `.fluoh/reports/<scope>/summary-<timestamp>.md` for multi-package monorepo work, run `$_reportCheckCommand`, then run `fluoh package check --package <name> --report .fluoh/reports/<name>/report-<timestamp>.md`. `.fluoh/` is ignored local state and must not be committed, so the worktree should remain clean for package check. Add `--require-ohos-run` when an OHOS target was available and the handoff must prove a passed real run. Maintainers can still use baseline `fluoh package check --package <name>` after their own manual verification. Release only after maintainer approval with `fluoh package release --package <name>`.',
    '',
  ];
}

List<String> _singleAdaptationCommandFlowLines(
  PackageRepositoryDocPackage package,
) {
  return [
    '## Automatic Adaptation Command Flow',
    '',
    'Use this command flow as the primary loop. The detailed workflow and platform matrix below add context, but these commands decide when to edit, when to fix local environment, and when the work can be handed back.',
    '',
    '1. Repository setup: use `fluoh package create <upstream> --repository-name <repository-name>` for a new repository and `fluoh package sync` only after a completed clean checkpoint when an upstream package release needs to be merged. Omitted upstream targets resolve to the latest valid package release tag; use `--upstream-version <version>` only when adapting a specific same-or-newer upstream version. `fluoh package sync` refuses upstream downgrades; mark the current adaptation `broken` with `fluoh package version --status broken` instead.',
    '2. Baseline gates: run `fluoh deps get`, `fluoh doctor --project --json --strict`, `fluoh flutter analyze`, and existing package or example tests before adding OHOS code. Project warnings mean repository fixes; environment warnings mean local toolchain or Source fixes.',
    '3. Implementation loop: after code, dependency, SDK, or metadata changes, rerun `fluoh deps get` when needed, then `${package.verifyCommand} --json --trace-dir <trace-dir>` until pub get, analysis, and existing tests pass.',
    '4. OHOS loop: run `${package.ohosRunCommand} --trace-dir <trace-dir>`, or `${package.ohosDeviceRunCommand} --trace-dir <trace-dir>` for a connected OHOS target. This prepares debug signing, launches through `flutter run`, captures run/session evidence, and executes `${package.examplePath}/integration_test/` on the selected target when present. If no local target can be started, run `${package.ohosBuildCommand} --trace-dir <trace-dir>` as build-only evidence and record the environment blocker.',
    '5. Existing-platform loop: for Android, run `fluoh doctor --platform android --json --strict`, then `${package.androidEmulatorRunCommand}` when `${package.examplePath}/android` exists. For iOS, run `fluoh doctor --platform ios --json --strict`, then `${package.iosSimulatorRunCommand}` when `${package.examplePath}/ios` exists. For macOS, run `fluoh doctor --platform macos --json --strict`, then `${package.macosRunCommand}` when `${package.examplePath}/macos` exists. For Web, run `fluoh doctor --platform web --json --strict`, then `${package.webRunCommand}` when `${package.examplePath}/web` exists. For Linux and Windows, run the matching doctor command and `${package.linuxBuildCommand}` or `${package.windowsBuildCommand}` when `${package.examplePath}/linux` or `${package.examplePath}/windows` exists. Add or run `${package.examplePath}/integration_test/` for tappable workflows; otherwise run an AI-assisted interaction scenario or manual-assisted fallback and record the reviewer, target, result, blocker, and tool-readable evidence beyond launch-only session state.',
    '6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`, `stderrTail`, saved logs, verify `dirtyAfterVerify`/`workingTreeChanges`, trace manifest `result`, and trace `feedbackCandidates` before editing. Fix `doctor` failures in local tooling, project warnings in repository configuration, unexpected generated-file changes, and verification failures in the package or example that produced the diagnostic.',
    '7. Implementation checkpoint: once implementation, OHOS evidence, and applicable existing-platform regression checks are clean or explicitly blocked, create a local implementation checkpoint commit. This clean worktree is required before `${package.versionCommand}`, `fluoh package sync`, and `${package.releaseCheckCommand}`.',
    '8. Release metadata checkpoint: run `${package.statusCommand}`, update release metadata with `${package.versionCommand}` when needed, update `FLUOH_CHANGELOG.md`, review `fluoh.yaml`, then create a local release metadata checkpoint commit. `${package.versionCommand}` requires a clean worktree before it writes metadata.',
    '9. Final report and release gate: rerun final `${package.verifyCommand}`, create `.fluoh/reports/${package.name}/report-<timestamp>.md` with command results, platform matrix, automation coverage gates, interaction evidence, diagnostics, Fluoh Feedback entries from trace manifests or an explicit `No fluoh feedback: <reason>` statement, signing mode, logs, risks, and release recommendation, run `$_reportCheckCommand`, then run `${package.releaseCheckCommand} --report .fluoh/reports/${package.name}/report-<timestamp>.md`. `.fluoh/` is ignored local state and must not be committed, so the worktree should remain clean for package check. Add `--require-ohos-run` when an OHOS target was available and the handoff must prove a passed real run. Maintainers can still use baseline `${package.releaseCheckCommand}` after their own manual verification. Release only after maintainer approval with `${package.releaseCommand}`.',
    '',
  ];
}

List<String> _multiPlatformVerificationLines() {
  return [
    '## Platform Verification Matrix',
    '',
    '- OHOS: run `fluoh run ohos --package <name> --auto-emulator --json`, or add `--device-id <id>` for a connected OHOS target. This is the authoritative OHOS signing-preparation, Flutter run, diagnostics, session, and integration-test loop. If `integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- Android: when `example/android` exists, first run `fluoh doctor --platform android --json --strict`, then run `fluoh run android --package <name> --auto-emulator --json` to prefer a local emulator, or add `--device-id <id>` only when no emulator is available. If `integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- iOS: when `example/ios` exists, first run `fluoh doctor --platform ios --json --strict`, then run `fluoh run ios --package <name> --auto-emulator --json` to prefer a simulator, or add `--device-id <id>` only when no simulator is available. If `integration_test/` exists, the command runs it on the selected target after the smoke run. Do not commit team-specific signing state.',
    '- macOS: when `example/macos` exists, first run `fluoh doctor --platform macos --json --strict`, then run `fluoh run macos --package <name> --json` on the local host. If `integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- Linux: when `example/linux` exists, first run `fluoh doctor --platform linux --json --strict`, then run `fluoh build linux --package <name> --json` on a Linux host. If a Linux run smoke is required, use `fluoh run linux --package <name> --json` on that host.',
    '- Web: when `example/web` exists, first run `fluoh doctor --platform web --json --strict`, then run `fluoh run web --package <name> --json` for browser smoke evidence. Add `fluoh build web --package <name> --json` when a separate web compile check is needed; pass `--device-id <browser-id>` only when multiple browser targets are available.',
    '- Windows: when `example/windows` exists, first run `fluoh doctor --platform windows --json --strict`, then run `fluoh build windows --package <name> --json` on a Windows host. If a Windows run smoke is required, use `fluoh run windows --package <name> --json` on that host.',
    '- For run smoke checks, `fluoh run` records platform launch evidence and can write a `flutterRunSession` file with `--session-file <path>`. Platform runs launch through `flutter run`, capture output for `--log-duration`, capture `details.vmServiceUri` when Flutter prints a VM Service or debug service URI, send `d` to detach while leaving the app running, save output under `\$FLUOH_HOME/cache/package-runs`, and report runtime failures through JSON diagnostics. OHOS hdc/hilog evidence belongs to `fluoh drive` scenarios or lower-level debug diagnostics, not the primary run path. AI agents can run `python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>` to wait for launch evidence, then use `fluoh attach <platform> --session-file <path>` to attach through Flutter debug tooling, inspect logs, or route a failure without screenshot recognition.',
    '- Run smoke is not enough for workflows that need UI taps, permission prompts, files, camera, location, media playback, deep links, or external apps. Cover those flows with `integration_test/`, or run an AI-assisted functional scenario and record exact steps, expected result, actual result, device or simulator id, Flutter debug/widget/semantic/log evidence, and optional screenshots.',
    '- Store scenario notes under `.fluoh/scenarios/<package>/<platform>-<name>.md` when the interaction is not already encoded as `integration_test`. The AI driver follows the scenario, operates the target with available device or UI tools, and records pass/fail evidence in the report. The scenario must be usable without screenshot recognition or UI appearance judgment by relying on Flutter debug or VM service output, widget/component tree state, semantics, stable text, command JSON, or logs.',
    '- Consider every applicable interaction class before release: permission grant and denial, file or media picker, camera or microphone capture, location and sensors, maps, media playback or recording, deep links and external app callbacks, background or lifecycle behavior, multi-step forms, and negative/error paths. If none apply, write `No interaction required: <reason>` in the report.',
    '- OHOS `fluoh run` executes `integration_test/` when present. For required flows that are not yet encoded as integration tests, add tests first; use AI-assisted evidence or manual-assisted tool-readable evidence only when automation is explicitly blocked, and record the blocker plus evidence beyond launch-only session state.',
    '- Release recommendation `ready` requires passing build and run or integration evidence for every existing supported platform directory. A missing local Android, Xcode, macOS/Linux/Web/Windows host or browser, device, or simulator environment is a maintainer-decision blocker, not a ready release.',
    '- Record each platform as `not present`, `passed`, `failed`, or `skipped with blocker` in the `.fluoh/reports/<package-or-scope>/report-<timestamp>.md` platform matrix. Include command, device id or simulator id, exit result, and relevant output tail.',
    '',
  ];
}

List<String> _singlePlatformVerificationLines(
  PackageRepositoryDocPackage package,
) {
  return [
    '## Platform Verification Matrix',
    '',
    '- OHOS: run `${package.ohosRunCommand}`, or `${package.ohosDeviceRunCommand}` for a connected OHOS target. This is the authoritative OHOS signing-preparation, Flutter run, diagnostics, session, and integration-test loop. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- Android: when `${package.examplePath}/android` exists, first run `fluoh doctor --platform android --json --strict`, then run `${package.androidEmulatorRunCommand}` or `${package.androidRunCommand} --device-id <id>` for an already connected target. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- iOS: when `${package.examplePath}/ios` exists, first run `fluoh doctor --platform ios --json --strict`, then run `${package.iosSimulatorRunCommand}` on a simulator or `${package.iosRunCommand} --device-id <id>` for an already connected target. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run. Do not commit team-specific signing state.',
    '- macOS: when `${package.examplePath}/macos` exists, first run `fluoh doctor --platform macos --json --strict`, then run `${package.macosRunCommand}` on the local host. If `${package.examplePath}/integration_test/` exists, the command runs it on the selected target after the smoke run.',
    '- Linux: when `${package.examplePath}/linux` exists, first run `fluoh doctor --platform linux --json --strict`, then run `${package.linuxBuildCommand}` on a Linux host. If a Linux run smoke is required, use `${package.linuxRunCommand}` on that host.',
    '- Web: when `${package.examplePath}/web` exists, first run `fluoh doctor --platform web --json --strict`, then run `${package.webRunCommand}` for browser smoke evidence. Add `${package.webBuildCommand}` when a separate web compile check is needed; pass `--device-id <browser-id>` only when multiple browser targets are available.',
    '- Windows: when `${package.examplePath}/windows` exists, first run `fluoh doctor --platform windows --json --strict`, then run `${package.windowsBuildCommand}` on a Windows host. If a Windows run smoke is required, use `${package.windowsRunCommand}` on that host.',
    '- For run smoke checks, `fluoh run` records platform launch evidence and can write a `flutterRunSession` file with `--session-file <path>`. Platform runs launch through `flutter run`, capture output for `--log-duration`, capture `details.vmServiceUri` when Flutter prints a VM Service or debug service URI, send `d` to detach while leaving the app running, save output under `\$FLUOH_HOME/cache/package-runs`, and report runtime failures through JSON diagnostics. OHOS hdc/hilog evidence belongs to `fluoh drive` scenarios or lower-level debug diagnostics, not the primary run path. AI agents can run `python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>` to wait for launch evidence, then use `fluoh attach <platform> --session-file <path>` to attach through Flutter debug tooling, inspect logs, or route a failure without screenshot recognition.',
    '- Run smoke is not enough for workflows that need UI taps, permission prompts, files, camera, location, media playback, deep links, or external apps. Cover those flows with `${package.examplePath}/integration_test/`, or run an AI-assisted functional scenario and record exact steps, expected result, actual result, device or simulator id, Flutter debug/widget/semantic/log evidence, and optional screenshots.',
    '- Store scenario notes under `.fluoh/scenarios/${package.name}/<platform>-<name>.md` when the interaction is not already encoded as `integration_test`. The AI driver follows the scenario, operates the target with available device or UI tools, and records pass/fail evidence in the report. The scenario must be usable without screenshot recognition or UI appearance judgment by relying on Flutter debug or VM service output, widget/component tree state, semantics, stable text, command JSON, or logs.',
    '- Consider every applicable interaction class before release: permission grant and denial, file or media picker, camera or microphone capture, location and sensors, maps, media playback or recording, deep links and external app callbacks, background or lifecycle behavior, multi-step forms, and negative/error paths. If none apply, write `No interaction required: <reason>` in the report.',
    '- OHOS `${package.ohosRunCommand}` executes `${package.examplePath}/integration_test/` when present. For required flows that are not yet encoded as integration tests, add tests first; use AI-assisted evidence or manual-assisted tool-readable evidence only when automation is explicitly blocked, and record the blocker plus evidence beyond launch-only session state.',
    '- Release recommendation `ready` requires passing build and run or integration evidence for every existing supported platform directory. A missing local Android, Xcode, macOS/Linux/Web/Windows host or browser, device, or simulator environment is a maintainer-decision blocker, not a ready release.',
    '- Record each platform as `not present`, `passed`, `failed`, or `skipped with blocker` in the `.fluoh/reports/${package.name}/report-<timestamp>.md` platform matrix. Include command, device id or simulator id, exit result, and relevant output tail.',
    '',
  ];
}

List<String> _diagnosticsRoutingLines() {
  return [
    '## Diagnostics Routing',
    '',
    'When `fluoh run <platform> --json` fails, read the failed package or step `nextCommand`, `stdoutTail`/`stderrTail`, and route by `diagnostics[].code` before editing:',
    '',
    '- `dart.sdk_constraint_unsatisfied`: keep the selected latest upstream package version and adapt the package to the selected FlutterOH SDK. First adjust `pubspec.yaml` `environment.sdk` and example config only when the code can support the selected Dart version, using `details.sdkConstraint.suggestedEnvironmentSdkConstraint` when present, then replace newer Dart language, SDK API, or dependency usage until verify passes. Do not downgrade upstream unless maintainers explicitly approve an older baseline.',
    '- `dart.pub_get_failed`: fix dependency declarations or local path overrides after the selected SDK compatibility policy is clear.',
    '- `dart.analysis_failed`: fix Dart code or generated bindings until analysis passes.',
    '- `dart.test_failed`: fix package or example behavior, then rerun tests.',
    '- `ohos.hap_build_failed`: fix OHOS project config, ArkTS, permissions, `reason`, `usedScene`, resources, or FlutterOH build errors.',
    '- `android.apk_build_failed`: fix Android project config, Gradle/Kotlin/Java code, shared Dart changes, or dependency regressions.',
    '- `ios.build_failed`: fix iOS project config, Swift/Objective-C code, shared Dart changes, dependency regressions, or document a local Xcode/toolchain blocker. The iOS build uses `--no-codesign`.',
    '- `macos.build_failed`: fix macOS project config, Swift/Objective-C code, shared Dart changes, dependency regressions, or document a local macOS/Xcode blocker.',
    '- `linux.build_failed`, `windows.build_failed`: fix Linux/Windows desktop project config, C++ build files, shared Dart changes, dependency regressions, or document the missing matching host/toolchain blocker.',
    '- `web.build_failed`: fix Web project config, assets, conditional imports, plugin web registration, shared Dart changes, or dependency regressions.',
    '- `android.devices_failed`, `android.emulators_failed`, `ios.devices_failed`, `ios.emulators_failed`, `macos.devices_failed`, `linux.devices_failed`, `web.devices_failed`, `windows.devices_failed`: run `fluoh doctor --platform <platform> --json --strict` and fix native target tooling before editing package logic.',
    '- `android.device_missing`, `ios.device_missing`, `macos.device_missing`, `linux.device_missing`, `web.device_missing`, `windows.device_missing`: connect a matching target, use the matching desktop host, choose a Web target, or rerun the platform run command so fluoh can start a local emulator/simulator where available.',
    '- `android.device_not_found`, `ios.device_not_found`, `macos.device_not_found`, `linux.device_not_found`, `web.device_not_found`, `windows.device_not_found`: use an actual id from failed diagnostics or `fluoh devices --platform <platform>`.',
    '- `android.device_ambiguous`, `ios.device_ambiguous`, `macos.device_ambiguous`, `linux.device_ambiguous`, `web.device_ambiguous`, `windows.device_ambiguous`: pick one target and rerun with `--device-id <id>`.',
    '- `android.emulator_missing`, `ios.emulator_missing`, `macos.emulator_missing`, `linux.emulator_missing`, `web.emulator_missing`, `windows.emulator_missing`: create a local Android emulator or iOS simulator before rerunning the platform run command; desktop and Web platforms have no emulator, so use the matching local host or Web target.',
    '- `android.emulator_not_found`, `ios.emulator_not_found`, `macos.emulator_not_found`, `linux.emulator_not_found`, `web.emulator_not_found`, `windows.emulator_not_found`: choose an emulator from diagnostics and rerun with `--emulator <name>`; desktop and Web platforms should be rerun without `--emulator`.',
    '- `android.emulator_ambiguous`, `ios.emulator_ambiguous`, `macos.emulator_ambiguous`, `linux.emulator_ambiguous`, `web.emulator_ambiguous`, `windows.emulator_ambiguous`: pick one emulator from diagnostics and rerun with `--emulator <name>`.',
    '- `android.emulator_start_failed`, `ios.emulator_start_failed`, `macos.emulator_start_failed`, `linux.emulator_start_failed`, `web.emulator_start_failed`, `windows.emulator_start_failed`: inspect native emulator launch output from `fluoh run` and repair the local emulator/simulator, or rerun desktop and Web platforms without `--emulator`.',
    '- `android.launch_timeout`, `ios.launch_timeout`, `macos.launch_timeout`, `linux.launch_timeout`, `web.launch_timeout`, `windows.launch_timeout`: inspect run output, increase `--device-timeout` if the first launch is slow, or fix startup hangs.',
    '- `ohos.run_failed`, `android.run_failed`, `ios.run_failed`, `macos.run_failed`, `linux.run_failed`, `web.run_failed`, `windows.run_failed`: inspect `stdoutTail`/`stderrTail` and saved output logs, then fix device, signing, dependency, or runtime startup failures.',
    '- `android.runtime_crash`, `ios.runtime_crash`, `macos.runtime_crash`, `linux.runtime_crash`, `web.runtime_crash`, `windows.runtime_crash`: inspect the saved `outputLog` and fix the app crash or platform-channel failure.',
    '- `ohos.integration_test_failed`, `android.integration_test_failed`, `ios.integration_test_failed`, `macos.integration_test_failed`, `linux.integration_test_failed`, `web.integration_test_failed`, `windows.integration_test_failed`: fix integration test failures or the exercised example behavior.',
    '- `ohos.devices_failed`: run `fluoh doctor --platform ohos --json --strict` and fix FlutterOH device discovery before editing package logic.',
    '- `ohos.toolchain_missing`: install the OpenHarmony SDK toolchain with DevEco Studio or set `FLUOH_DEVECO_STUDIO`; do not edit package code for this.',
    '- `ohos.ohos_project_missing`: create or repair the example `ohos/` platform before signing or running.',
    '- `ohos.auto_sign_failed`: inspect the signing diagnostic and fix the project metadata or local toolchain before editing package logic.',
    '- `ohos.signing_profile_failed`: fix generated debug profile inputs, permissions, or local signing tools.',
    '- `ohos.build_profile_patch_failed`: fix `example/ohos/build-profile.json5` shape so temporary signing can be applied.',
    '- `ohos.direct_sign_failed`: inspect the HAP signing output and fix signing material or generated unsigned HAP state.',
    '- `ohos.launch_info_missing`: fix `AppScope/app.json5` or `module.json5` when a debug scenario needs bundle and ability metadata.',
    '- `ohos.hdc_targets_failed`: fix the hdc debug-tool or emulator environment before running drive scenarios.',
    '- `ohos.emulator_start_failed`: create or repair a local OpenHarmony emulator, or rerun with `--device-id <id>`.',
    '- `ohos.device_missing`: rerun the OHOS run command with `--auto-emulator`, start an OpenHarmony emulator, or connect a device and add `--device-id <id>`.',
    '- `ohos.device_not_found`: use an actual id from `flutter devices --machine` or `fluoh devices --platform ohos`.',
    '- `ohos.device_ambiguous`: pick one target and rerun with `--device-id <id>`.',
    '- `ohos.no_installable_hap`: ensure the build-only or debug-tool HAP flow produced a signed or directly signable output.',
    '- `ohos.install_failed`: inspect debug-tool install stdout/stderr; fix signing, bundle conflicts, SDK mismatch, or device state.',
    '- `ohos.launch_failed`: fix bundle name, ability name, module metadata, permissions, or startup crash in the debug-tool flow.',
    '- `ohos.runtime_crash`: inspect the saved `outputLog`, or hilog when a drive/debug scenario produced it, then fix the crash or Flutter channel runtime error and rerun.',
    '- `command.failed`: read the command, stdout, and stderr, then classify the failure manually.',
    '- Do not create a broad "all permissions" signature. Let `--auto-sign` regenerate the debug signing profile from the example\'s current permission declarations.',
    '',
    'Dependency status routing (from `fluoh deps check --json` and `fluoh deps fix --json`):',
    '',
    '- `unknown`: no OHOS implementation exists. Report in the completion report under "Unavailable"; do not attempt to implement the dependency yourself unless the maintainer asks.',
    '- `blocked`: source index marks this package as blocked for OHOS. Report in the completion report; note the block reason for the maintainer.',
    '- `sdk-mismatch`: OHOS implementations exist for other SDK lines but not the selected one. Report available SDK lines in the completion report; suggest switching SDK version or ask the maintainer.',
    '- `incompatible-version`: locked version has no exact or compatible implementation. Report in the completion report; suggest setting `dependencyPolicy.versionChanges` to `any` in `fluoh.yaml` if the maintainer accepts breaking changes.',
    '',
    'Sync and merge routing (from `fluoh package sync --json`):',
    '',
    '- `sync.merge_conflict`: upstream target merge produced file conflicts. For `fluoh.yaml` metadata conflicts, accept the upstream version and re-apply local package metadata. For OHOS platform files (`ohos/`, platform channels), preserve local OHOS implementations and manually integrate upstream changes. For non-OHOS files, accept upstream, including the target package pubspec version. Run `fluoh package sync --continue` after staging resolved files; if the interrupted sync used a non-tag `--upstream-ref`, pass the same ref again with `--continue`.',
    '- `sync.merge_failed`: git could not merge the upstream target and did not leave resolvable file conflicts. Inspect `stderrTail`, fix the branch or repository state, then retry `fluoh package sync --json`.',
    '- `sync.fetch_failed`: upstream fetch failed, likely a network issue. Verify network access to the upstream repository, then retry.',
    '',
  ];
}

List<String> _completionReportLines() {
  return [
    '## Completion Report',
    '',
    '- Before final response, create a timestamped report in the repository root under `.fluoh/reports/<package-or-scope>/report-<timestamp>.md`. For multi-package monorepos, also create `.fluoh/reports/<scope>/summary-<timestamp>.md`. Use a Unix epoch milliseconds timestamp, for example `.fluoh/reports/camera/report-1781092800123.md`. Create `.fluoh/reports/<package-or-scope>/` if needed; it is local state and must not be committed.',
    '- The report must include: package name, upstream version, FlutterOH SDK version, implementation summary, changed files, public API changes if any, permissions and OHOS config changes, commands run with exit results and relevant output tails, final `fluoh run <platform> --json` or build outcome, a platform matrix for OHOS/Android/iOS/macOS/Linux/Web/Windows with build, run, integration-test, device/simulator/host/browser, and skip-blocker fields, real `fluoh drive --json` evidence, automation coverage gates from dry-run or real drive JSON, functional interaction evidence for required scenarios, signing mode, generated HAP paths, hilog path when present, remaining risks, and release recommendation.',
    '- End the report with one of: `Release recommendation: ready`, `Release recommendation: needs maintainer decision`, or `Release recommendation: blocked`, followed by the exact reason.',
    '- If the maintainer asks for another iteration, create a new timestamped report for that completed iteration so earlier reports remain available.',
    '',
  ];
}

/// Builds generated `FLUOH.md` implementation guidance.
String packageImplementationGuideContent({
  required List<PackageRepositoryDocPackage> packages,
  required bool includeTitle,
}) {
  if (packages.length == 1) {
    return _singlePackageImplementationGuideContent(
      package: packages.single,
      includeTitle: includeTitle,
    );
  }

  return [
    if (includeTitle) '# FlutterOH Implementation',
    if (includeTitle) '',
    'This repository is being used for a package-branch adaptation queue. Current SDK, package path, upstream version, release version, and release status are recorded in the current branch `fluoh.yaml`.',
    '',
    '## Packages',
    '',
    for (final package in packages)
      '- `${package.name}` ${package.version}: package path `${package.packagePath}`, example `${package.examplePath}`, verify command `${package.verifyCommand}`, version command `${package.versionCommand}`, release check `${package.releaseCheckCommand}`, release command `${package.releaseCommand}`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the current upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package metadata: `package` in the current branch `fluoh.yaml`',
    '- Repository URL/path: `repository.git.url` in `fluoh.yaml`',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '- Command help: `fluoh help`, `fluoh help package`, and `fluoh help verify`',
    '',
    '## Adaptation Checklist',
    '',
    '- For each package, confirm the Dart API surface, existing platform implementations, platform-channel or native entry points, permissions, configuration files, example flows, automated tests, and device-only checks before editing.',
    for (final package in packages)
      '- `${package.name}`: inspect `${package.packagePath}`, `${package.examplePath}`, package tests, example tests, and pubspec constraints.',
    '- Keep assumptions close to the current diff; remove stale notes before release.',
    '',
    ..._adaptationGuardrailLines(),
    ..._platformImplementationTemplateLines(),
    ..._multiAdaptationCommandFlowLines(),
    ..._multiPlatformVerificationLines(),
    ..._diagnosticsRoutingLines(),
    '## Next Steps',
    '',
    '1. Establish a selected-SDK and native-platform baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds. Include the matching Android/iOS/macOS run command and Linux/Web/Windows build command when the example has that platform directory and the local toolchain is available, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for the current package branch.',
    '3. Inspect upstream package tests, existing example tests, and `integration_test/` against public API, platform interfaces, permissions, success paths, and error paths. Add or repair missing functional tests before final verification.',
    '4. Keep package tests and example tests deterministic, with existing example apps for integration-test, AI-assisted, or manual-assisted tool-readable platform verification.',
    '5. Run the full automated OHOS loop for each package example: `fluoh run ohos --package <name> --auto-emulator --json`. Add `--device-id <id>` for an already connected OHOS target. Use `fluoh build ohos --package <name> --auto-sign --json` as a build-only fallback only when no local target can be started. JSON `nextCommand` and `diagnostics` give the next failure category. When `example/integration_test/` exists, the OHOS run command executes it on the selected target.',
    '6. Run existing-platform functional checks after shared or example changes when their platform directories exist: run `fluoh doctor --project --json --strict`, then use `fluoh run android --package <name> --auto-emulator --json` for Android, `fluoh run ios --package <name> --auto-emulator --json` for iOS, `fluoh run macos --package <name> --json` for macOS, `fluoh run web --package <name> --json` for Web, and `fluoh build linux|windows --package <name> --json` on matching Linux/Windows hosts. Add `--device-id <id>` only when no emulator or simulator is available, or when multiple browser targets are available. iOS builds use `--no-codesign`; document unavailable local Android/Xcode/macOS/Linux/Web/Windows host or browser toolchains instead of guessing. Add `integration_test/`, AI-assisted interaction evidence, or manual-assisted tool-readable evidence for flows beyond launch smoke.',
    '7. Run `fluoh doctor --project --json --strict` when local native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot state is unclear.',
    '8. Commit the implementation checkpoint before release metadata commands; `fluoh package version --package <name>` requires a clean worktree before it writes metadata.',
    '9. Use `fluoh package version --package <name>` and update `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change, then commit the release metadata checkpoint.',
    '10. Run final `fluoh verify --package <name>`, create the ignored `.fluoh/reports/<name>/report-<timestamp>.md`, run `$_reportCheckCommand`, then run `fluoh package check --package <name> --report <report-path>` while the tracked worktree is clean.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml` to confirm SDK version, package path, upstream version, current release status, and example location.',
    '2. Baseline: for each package, run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds with the selected SDK before changing OHOS code. Include Android/iOS/macOS run commands and Linux/Web/Windows build commands when those example platform directories exist and local toolchains are available; fix non-OHOS regressions first.',
    '3. Plan: inspect the upstream Dart API and platform implementations, then identify required OHOS entry points, permissions, config files, tests, example flows, and device checks.',
    '4. Implement: add OHOS code without changing upstream public APIs unless upstream requires it.',
    '5. Test: before running the final matrix, inspect whether existing package tests and example tests cover the package behavior. Add deterministic automated checks for missing arguments, return shapes, errors, permissions, and platform-channel names when applicable.',
    '6. Example: from each existing package example, run `fluoh sdk use <sdk-version> --pub-get` when the IDE link is missing or stale. Extend examples from their existing platforms plus OHOS, including operation, expected result, pass/fail status, and failure hint.',
    '7. Build and run OHOS: use `fluoh run ohos --package <name> --auto-emulator --json` to prepare signing, launch with `flutter run`, classify failures, and execute `example/integration_test/` when present. Fix permission, `reason`, `usedScene`, ArkTS, signing, run, runtime, or interaction diagnostics before release.',
    '8. Check existing platforms: follow the Platform Verification Matrix. Run `fluoh run android --package <name> --auto-emulator --json` when an Android example exists, `fluoh run ios --package <name> --auto-emulator --json` when an iOS example exists, `fluoh run macos --package <name> --json` when a macOS example exists, `fluoh run web --package <name> --json` when a Web example exists, and `fluoh build linux|windows --package <name> --json` when Linux or Windows examples exist on matching hosts. Add `--device-id <id>` only when no emulator or simulator is available, or when multiple browser targets are available. Use `integration_test/`, AI-assisted interaction evidence, or manual-assisted tool-readable evidence for scenario coverage beyond launch smoke. Record exact diagnostic commands and skip reasons only for unavailable local toolchains or unsupported hosts.',
    '9. Release prep: keep `package.release.status: experimental` until that package is implemented, tested, and ready to be recommended. Run `fluoh deps get` after dependency or metadata changes, run the matching `fluoh verify --package <name>`, then commit the implementation checkpoint.',
    '10. Finish: update release metadata, update `FLUOH_CHANGELOG.md`, commit the release metadata checkpoint, run final `fluoh verify --package <name>`, create the ignored `.fluoh/reports/<name>/report-<timestamp>.md`, run `$_reportCheckCommand`, then run `fluoh package check --package <name> --report <report-path>`. Use `fluoh package release --package <name>` only after maintainer approval.',
    '',
    '## Release Readiness',
    '',
    '- Public Dart APIs remain compatible with upstream unless upstream changed them.',
    '- Automated package and example tests were inspected before final verification and cover the adapted behavior; missing or weak functional tests were added or have a concrete blocker.',
    '- Device-only behavior and UI interaction flows have an automated `integration_test`, AI-assisted interaction evidence, manual-assisted tool-readable evidence, or a clear remaining blocker.',
    '- The full OHOS run succeeds when a local emulator or device is available; otherwise the device-only blocker is documented.',
    '- Android, iOS, macOS, Linux, Web, and Windows example checks pass when those platforms exist and local toolchains are available; mobile, macOS, and Web checks include run smoke/integration evidence, and Linux and Windows at least pass desktop builds on matching hosts. Unavailable toolchains are documented with exact skipped commands and block a `ready` recommendation.',
    '- `FLUOH_CHANGELOG.md`, `fluoh.yaml`, package status, and release version are ready for `fluoh package check` and `fluoh package release`.',
    '',
    ..._completionReportLines(),
    ..._localCommitCheckpointLines(multiPackage: true),
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

String _singlePackageImplementationGuideContent({
  required PackageRepositoryDocPackage package,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# FlutterOH Implementation',
    if (includeTitle) '',
    'This repository contains the OHOS implementation for `${package.name}`. Current SDK, package path, upstream version, release version, and release status are recorded in `fluoh.yaml`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package metadata: `package` in `fluoh.yaml`',
    '- Upstream version: `${package.version}`',
    '- Package path: `package.path` in `fluoh.yaml`',
    '- Repository URL/path: `repository.git.url` in `fluoh.yaml`',
    '- Repository branch: `repository.git.branch` in `fluoh.yaml`',
    '- Upstream repository: `upstream.git` in `fluoh.yaml`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '- Command help: `fluoh help`, `fluoh help package`, and `fluoh help verify`',
    '',
    '## Adaptation Checklist',
    '',
    '- Confirm the Dart API surface, existing platform implementations, platform-channel or native entry points, permissions, configuration files, example flows, automated tests, and device-only checks before editing.',
    '- Inspect `${package.packagePath}`, `${package.examplePath}`, package tests, example tests, and pubspec constraints.',
    '- Keep assumptions close to the current diff; remove stale notes before release.',
    '',
    ..._federatedImplementationRouteLines(package),
    ..._adaptationGuardrailLines(),
    ..._platformImplementationTemplateLines(package: package),
    ..._singleAdaptationCommandFlowLines(package),
    ..._singlePlatformVerificationLines(package),
    ..._diagnosticsRoutingLines(),
    '## Next Steps',
    '',
    '1. Establish a selected-SDK and native-platform baseline before adding OHOS code: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds. Include the matching Android/iOS/macOS run command and Linux/Web/Windows build command when the example has that platform directory and the local toolchain is available, then fix non-OHOS platform regressions first.',
    '2. Implement the OHOS platform code for `${package.name}`.',
    '3. Inspect upstream package tests, existing example tests, and `integration_test/` against public API, platform interfaces, permissions, success paths, and error paths. Add or repair missing functional tests before final verification.',
    '4. Keep package tests and example tests deterministic. When `${package.examplePath}` exists, inspect the existing Android/iOS/macOS/Linux/Web/Windows example flows and `integration_test/` first, then make the OHOS example cover equivalent entry points, labels, permissions, status text, expected results, and failure hints unless the platform capability is unavailable.',
    '5. Run the full automated OHOS loop when an example is available: `${package.ohosRunCommand}`. Use `${package.ohosDeviceRunCommand}` for an already connected OHOS target. Use `${package.ohosBuildCommand}` as a build-only fallback only when no local target can be started. JSON `nextCommand` and `diagnostics` give the next failure category. When `${package.examplePath}/integration_test/` exists, the OHOS run command executes it on the selected target.',
    '6. Run existing-platform functional checks after shared or example changes when their platform directories exist: run `fluoh doctor --project --json --strict`, then use `${package.androidEmulatorRunCommand}` for Android, `${package.iosSimulatorRunCommand}` for iOS, `${package.macosRunCommand}` for macOS, `${package.webRunCommand}` for Web, `${package.linuxBuildCommand}` for Linux, and `${package.windowsBuildCommand}` for Windows, or add `--device-id <id>` for already connected mobile targets. iOS builds use `--no-codesign`; document unavailable local Android/Xcode/macOS/Linux/Web/Windows host or browser toolchains instead of guessing. Add `${package.examplePath}/integration_test/`, AI-assisted interaction evidence, or manual-assisted tool-readable evidence for flows beyond launch smoke.',
    '7. Run `fluoh doctor --project --json --strict` when local native toolchains, connected targets, current project, selected SDK, fluoh installation, or source snapshot state is unclear.',
    '8. Commit the implementation checkpoint before release metadata commands; `${package.versionCommand}` requires a clean worktree before it writes metadata.',
    '9. Use `${package.versionCommand}` and update `FLUOH_CHANGELOG.md` when package version, upstream version, status, or release notes change, then commit the release metadata checkpoint.',
    '10. Run final `${package.verifyCommand}`, create the ignored `.fluoh/reports/${package.name}/report-<timestamp>.md`, run `$_reportCheckCommand`, then run `${package.releaseCheckCommand} --report <report-path>` while the tracked worktree is clean.',
    '',
    '## Adaptation Workflow',
    '',
    '1. Inventory: read `fluoh.yaml` to confirm SDK version, package path, upstream version, current release status, and example location.',
    '2. Baseline: run `fluoh deps get`, `fluoh flutter analyze`, `fluoh doctor --project --json --strict`, and existing package tests or example builds with the selected SDK before changing OHOS code. Include `${package.androidRunCommand}`, `${package.iosRunCommand}`, `${package.macosRunCommand}`, `${package.webRunCommand}`, `${package.linuxBuildCommand}`, or `${package.windowsBuildCommand}` when the matching example platform directory exists and local toolchains are available; fix non-OHOS regressions first.',
    '3. Plan: inspect the upstream Dart API and platform implementations, then identify required OHOS entry points, permissions, config files, tests, example flows, and device checks.',
    '4. Implement: add OHOS code under the package path recorded in `fluoh.yaml` without changing upstream public APIs unless upstream requires it.',
    '5. Test: before running the final matrix, inspect whether existing package tests and example tests cover the package behavior. Add deterministic automated checks for missing arguments, return shapes, errors, permissions, and platform-channel names when applicable.',
    '6. Example: from `${package.examplePath}` when it exists, run `fluoh sdk use <sdk-version-from-fluoh.yaml> --pub-get` when the IDE link is missing or stale. Use the existing Android/iOS/macOS/Linux/Web/Windows example flows and `integration_test/` as the reference, then extend the example with OHOS parity: operation, expected result, pass/fail status, permission prompts, status text, and failure hint.',
    '7. Build and run OHOS: use `${package.ohosRunCommand}` to prepare signing, launch with `flutter run`, classify failures, and execute `${package.examplePath}/integration_test/` when present. Fix permission, `reason`, `usedScene`, ArkTS, signing, run, runtime, or interaction diagnostics before release.',
    '8. Check existing platforms: follow the Platform Verification Matrix. Run `${package.androidEmulatorRunCommand}` when an Android example exists, `${package.iosSimulatorRunCommand}` when an iOS example exists, `${package.macosRunCommand}` when a macOS example exists, `${package.webRunCommand}` when a Web example exists, `${package.linuxBuildCommand}` when a Linux example exists, and `${package.windowsBuildCommand}` when a Windows example exists, or add `--device-id <id>` for already connected mobile targets. Use `${package.examplePath}/integration_test/`, AI-assisted interaction evidence, or manual-assisted tool-readable evidence for scenario coverage beyond launch smoke. Record exact diagnostic commands and skip reasons only for unavailable local toolchains or unsupported hosts.',
    '9. Release prep: keep `package.release.status: experimental` until the implementation is complete, tested, and ready to be recommended. Run `fluoh deps get` after dependency or metadata changes, run `${package.verifyCommand}`, then commit the implementation checkpoint.',
    '10. Finish: update `FLUOH_CHANGELOG.md`, commit the release metadata checkpoint, run final `${package.verifyCommand}`, create the ignored `.fluoh/reports/${package.name}/report-<timestamp>.md`, run `$_reportCheckCommand`, then run `${package.releaseCheckCommand} --report <report-path>`. Use `${package.releaseCommand}` only after maintainer approval.',
    '',
    '## Release Readiness',
    '',
    '- Public Dart APIs remain compatible with upstream unless upstream changed them.',
    '- Automated package and example tests were inspected before final verification and cover the adapted behavior; missing or weak functional tests were added or have a concrete blocker.',
    '- Device-only behavior and UI interaction flows have an automated `integration_test`, AI-assisted interaction evidence, manual-assisted tool-readable evidence, or a clear remaining blocker.',
    '- `${package.ohosRunCommand}` succeeds when a local emulator is available; otherwise the device-only blocker is documented.',
    '- `${package.androidRunCommand}`, `${package.iosRunCommand}`, `${package.macosRunCommand}`, and `${package.webRunCommand}` run smoke checks and integration tests when those platforms exist and local toolchains are available; `${package.linuxBuildCommand}` and `${package.windowsBuildCommand}` pass when Linux or Windows examples exist on matching hosts; unavailable toolchains are documented with exact skipped commands and block a `ready` recommendation.',
    '- `FLUOH_CHANGELOG.md`, `fluoh.yaml`, package status, and release version are ready for `${package.releaseCommand}`.',
    '',
    ..._completionReportLines(),
    ..._localCommitCheckpointLines(multiPackage: false),
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

List<String> _federatedImplementationRouteLines(
  PackageRepositoryDocPackage package,
) {
  final recommendation = package.implementationRecommendation;
  if (recommendation == null) {
    return const [];
  }
  return [
    '## Federated Implementation Route',
    '',
    '- Keep the Source route and public API on app-facing package `${recommendation.appFacingPackage}`.',
    '- Create the OHOS implementation package `${recommendation.implementationPackageName}` at `${recommendation.implementationPackagePath}`.',
    '- Add `${recommendation.platform}.default_package: ${recommendation.implementationPackageName}` to `${recommendation.appFacingPackage}`.',
    '- Add dependency `${recommendation.implementationPackageName}` with relative path `${recommendation.implementationDependencyPath}`.',
    '- Use existing default packages as parity references: ${_defaultPackageSummary(recommendation.existingDefaultPackages)}.',
    '',
  ];
}

List<String> _platformImplementationTemplateLines({
  PackageRepositoryDocPackage? package,
}) {
  final packageName = package?.name ?? '<package-name>';
  final examplePath = package?.examplePath ?? '<example-path>';
  return [
    '## Platform Implementation Template',
    '',
    '- Keep the public Dart API, example UI, tests, and report language platform-neutral. Put shared validation, argument normalization, result mapping, error handling, and fallback decisions in one Dart facade.',
    '- Keep Android, iOS, and OHOS behavior behind platform-specific adapters. The app-facing layer should call the same adapter methods for every platform, and platform switching should live in one factory or package registration point.',
    '- Use existing Android and iOS implementations as parity references, then implement OHOS-specific entry points under `ohos/` or the OHOS federated implementation package. Do not scatter repeated `Platform.is...` branches through widgets, examples, or public APIs.',
    '- Preserve upstream method names, channel names, result keys, exception codes, and permission semantics when they are part of the package contract. If OHOS cannot support a capability, return the same unsupported or unavailable shape consistently through the facade.',
    '',
    '### Facade Shape',
    '',
    '```dart',
    'abstract interface class PackagePlatformAdapter {',
    '  Future<PackageResult> perform(PackageRequest request);',
    '}',
    '',
    'final class PackageFacade {',
    '  PackageFacade({PackagePlatformAdapter? adapter})',
    '    : _adapter = adapter ?? createPackagePlatformAdapter();',
    '',
    '  final PackagePlatformAdapter _adapter;',
    '',
    '  Future<PackageResult> perform(PackageRequest request) async {',
    '    final normalized = request.normalized();',
    '    final result = await _adapter.perform(normalized);',
    '    return result.normalized();',
    '  }',
    '}',
    '```',
    '',
    '### Adapter Factory Shape',
    '',
    '```dart',
    'PackagePlatformAdapter createPackagePlatformAdapter() {',
    "  switch (Platform.operatingSystem) {",
    "    case 'android':",
    '      return AndroidPackageAdapter();',
    "    case 'ios':",
    '      return IosPackageAdapter();',
    "    case 'ohos':",
    '      return OhosPackageAdapter();',
    '    default:',
    "      return UnsupportedPackageAdapter('unsupported platform');",
    '  }',
    '}',
    '```',
    '',
    '### Implementation Routes',
    '',
    '- Method-channel packages: keep one Dart channel interface and implement the same method names in `android/`, `ios/`, and `ohos/`. The facade owns request/result normalization; native code owns only platform APIs and platform-specific error conversion.',
    '- Federated packages: keep `$packageName` as the app-facing API and register the OHOS implementation as the OHOS default package. The OHOS package should implement the same platform-interface methods as Android/iOS implementations and keep channel result shapes compatible.',
    '- Permission or capability packages: model one shared request/result object in Dart, then map Android permissions, iOS entitlements, and OHOS permissions or `reason`/`usedScene` declarations inside the platform adapter. Do not expose OHOS-only permission strings through the public API unless upstream already exposes platform-specific configuration.',
    '- Example apps: keep flows under `$examplePath` platform-neutral. Add one reusable action path that works across Android, iOS, and OHOS, then record platform-specific skipped commands or blockers in the report instead of adding separate example screens.',
    '',
  ];
}

String _defaultPackageSummary(Map<String, String> packages) {
  return packages.entries
      .map((entry) => '${entry.key} -> ${entry.value}')
      .join(', ');
}

/// Builds the initial generated `FLUOH_CHANGELOG.md` content.
String packageFluohChangelogContent({
  required List<PackageRepositoryDocPackage> packages,
  required String sdkVersion,
  required String releaseVersion,
}) {
  return [
    '# FlutterOH Changelog',
    '',
    for (final package in packages)
      ...packageFluohChangelogEntryLines(
        package: package,
        sdkVersion: sdkVersion,
        releaseVersion: releaseVersion,
      ),
  ].join('\n');
}

/// Builds one generated changelog entry for a package release tag.
List<String> packageFluohChangelogEntryLines({
  required PackageRepositoryDocPackage package,
  required String sdkVersion,
  required String releaseVersion,
}) {
  final tag = packageReleaseTagForPackage(
    packageName: package.name,
    upstreamVersion: package.version,
    sdkVersion: sdkVersion,
    releaseVersion: releaseVersion,
  );
  return [
    '## $tag',
    '',
    '- TODO: Replace this generated placeholder with actual FlutterOH/OHOS release notes before release. Include implemented behavior, verification evidence, and remaining risks for `${package.name}` ${package.version} on FlutterOH SDK `$sdkVersion`.',
    '',
  ];
}
