part of 'package_port_command.dart';

extension on PackagePortCommand {
  Future<int> _runPlan({
    required String upstream,
    required List<String> packagePaths,
    required String repositoryName,
    required String? repositoryOption,
    required PackageUpstreamTarget upstreamTarget,
    required PackageGitAuthor? gitAuthor,
    required String? flutterCreateOrg,
    required SdkRelease release,
    required Directory destination,
    required bool json,
  }) async {
    Directory? tempRoot;
    try {
      tempRoot = await Directory.systemTemp.createTemp('fluoh-create-plan-');
      final scratchRepository = Directory('${tempRoot.path}/upstream');
      if (!json) {
        _output.step('Inspecting upstream repository');
      }
      final cloneMode = await _cloneUpstreamForPackagePortPlan(
        upstream: upstream,
        scratchRepository: scratchRepository,
        packagePaths: packagePaths,
        upstreamTarget: upstreamTarget,
      );
      final repositoryUrl =
          repositoryOption ?? defaultPackageRepositoryUrl(repositoryName);
      await configurePackageRemotes(scratchRepository, repositoryUrl);
      final upstreamBranch = await upstreamDefaultBranch(scratchRepository);
      await synchronizeUpstreamBranch(
        scratchRepository,
        branch: upstreamBranch,
      );
      await _prepareUpstreamRefsForPackagePortPlan(
        repository: scratchRepository,
        cloneMode: cloneMode,
        packagePaths: packagePaths,
        upstreamBranch: upstreamBranch,
        upstreamTarget: upstreamTarget,
      );
      final selectedPackages = await _selectPackagesForTarget(
        repository: scratchRepository,
        packagePaths: packagePaths,
        fallbackRef: upstreamBranch,
        target: upstreamTarget,
      );
      final selected = selectedPackages.single;
      final defaultBranchVersionWarning =
          await _defaultBranchPackageVersionWarning(
            repository: scratchRepository,
            selected: selected,
            upstreamBranch: upstreamBranch,
            upstreamTarget: upstreamTarget,
          );
      final branch = flutterOhosPackageBranchForSdk(
        sdkVersion: release.tag,
        packageName: selected.package.name,
      );
      await runGit([
        'checkout',
        '--detach',
        selected.upstreamCommit!,
      ], workingDirectory: scratchRepository);
      final implementationRecommendation =
          await _implementationRecommendationForSelectedPackage(
            repository: scratchRepository,
            selected: selected,
            missingPlatform: 'ohos',
          );
      final supportProfile = await _supportProfileForSelectedPackage(
        repository: scratchRepository,
        selected: selected,
      );
      final compatibilityWarnings = await packageSdkCompatibilityWarnings(
        repository: scratchRepository,
        selectedPackages: selectedPackages
            .map(
              (selected) => SelectedPackageForSdkCompatibility(
                package: selected.package,
                path: selected.path,
                upstreamRef: selected.upstreamRef,
              ),
            )
            .toList(),
        sdkDirectory: SdkManager(environment).sdkDirectory(release.tag),
      );
      final warnings = <_PackagePortWarning>[
        ?defaultBranchVersionWarning,
        ...compatibilityWarnings.map(_SdkCompatibilityPlanWarning.new),
      ];
      final plan = _PackagePortPlan(
        upstream: upstream,
        upstreamBranch: upstreamBranch,
        repositoryName: repositoryName,
        repositoryUrl: repositoryUrl,
        outputPath: destination.path,
        sdkVersion: release.tag,
        sdkLine: sdkLineFromSdkVersion(release.tag),
        packageName: selected.package.name,
        packagePath: selected.path,
        upstreamVersion: selected.package.version,
        upstreamRef: selected.upstreamRef,
        upstreamCommit: selected.upstreamCommit!,
        branch: branch,
        gitAuthor: gitAuthor,
        flutterCreateOrg: flutterCreateOrg,
        supportProfile: supportProfile,
        implementationRecommendation: implementationRecommendation,
        warnings: warnings,
      );
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'package port',
          ok: true,
          exitCode: 0,
          fields: {'changed': false, 'applied': false, 'plan': plan.toJson()},
        );
      } else {
        _printPlan(plan);
      }
      return 0;
    } finally {
      if (tempRoot != null && await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  }

  void _printPlan(_PackagePortPlan plan) {
    _output.success('Package port plan');
    _output.info('Repository name: ${plan.repositoryName}');
    _output.info('Output path: ${_output.style.path(plan.outputPath)}');
    _output.info('Origin: ${_output.style.url(plan.repositoryUrl)}');
    _output.info('Package: ${plan.packageName} at ${plan.packagePath}');
    _output.info('SDK: ${plan.sdkVersion} (${plan.sdkLine})');
    _output.info('Branch: ${plan.branch}');
    _output.info('Support profile: ${_planProfileLabel(plan.supportProfile)}');
    if (plan.gitAuthor != null) {
      _output.info(
        'Git author: ${plan.gitAuthor!.name} <${plan.gitAuthor!.email}>',
      );
    } else {
      _output.info('Git author: not configured by this command');
    }
    _output.info(
      plan.flutterCreateOrg == null
          ? 'Flutter create org: infer from example platforms'
          : 'Flutter create org: ${plan.flutterCreateOrg}',
    );
    final implementationRecommendation = plan.implementationRecommendation;
    if (implementationRecommendation != null) {
      _output.next(
        'Create ${implementationRecommendation.implementationPackageName} at '
        '${implementationRecommendation.implementationPackagePath} and add '
        '${implementationRecommendation.platform}.default_package to '
        '${implementationRecommendation.appFacingPackage}',
      );
    }
    for (final warning in plan.warnings) {
      _output.warning(warning.message);
      _output.next(warning.nextStep);
    }
    _output.next('Run without --plan after confirming these values');
  }

  Future<PackageSupportProfile> _supportProfileForSelectedPackage({
    required Directory repository,
    required _SelectedPackage selected,
  }) async {
    final discovery = await discoverPackageSupportCandidates(
      repository: repository,
      includeExistingPlatform: true,
    );
    for (final candidate in discovery.candidates) {
      if (candidate.path == selected.path ||
          candidate.name == selected.package.name) {
        return candidate.supportProfile;
      }
    }
    return inferPackageSupportProfile(
      name: selected.package.name,
      path: selected.path,
    );
  }

  String _planProfileLabel(PackageSupportProfile profile) {
    final categories = profile.categories.take(3).join(', ');
    if (categories.isEmpty) {
      return profile.complexity;
    }
    return '${profile.complexity}: $categories';
  }
}
