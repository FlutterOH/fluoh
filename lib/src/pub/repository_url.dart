String defaultPubRepositoryUrl(
  String packageName, {
  String base = 'git@github.com:FlutterOH',
}) {
  final normalized = packageName.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      packageName,
      'packageName',
      'Package name must not be empty.',
    );
  }
  final suffix = normalized.endsWith('.git') ? normalized : '$normalized.git';
  if (base.startsWith('git@') && !base.endsWith('/')) {
    return '$base/$suffix';
  }
  return '${base.replaceFirst(RegExp(r'/$'), '')}/$suffix';
}

String repositoryNameFromUpstream(String upstream) {
  final trimmed = upstream.trim();
  final withoutSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  final name = withoutSlash.split(RegExp(r'[:/]')).last;
  return name.endsWith('.git') ? name.substring(0, name.length - 4) : name;
}
