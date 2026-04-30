# Contributing to fluoh

本文档面向 `fluoh` 的贡献者和维护者。普通用户优先阅读 [README.md](README.md) 或 [README.en.md](README.en.md)。

## 本地开发

准备 Dart SDK 后安装依赖：

```sh
dart pub get
```

本地运行 CLI：

```sh
dart run bin/fluoh.dart --help
dart run bin/fluoh.dart --version
```

如果需要隔离本地配置和缓存，可以设置 `FLUOH_HOME`：

```sh
FLUOH_HOME=/path/to/cache dart run bin/fluoh.dart source list
```

## 验证

提交前至少运行：

```sh
dart format .
dart analyze
dart test
```

发布前额外运行：

```sh
dart pub publish --dry-run
```

如果本地 shell 的 `dart` 不稳定，可以显式使用 Flutter 缓存中的 Dart SDK，但不要把机器上的绝对路径写入仓库文件。

## 提交前检查

建议提交前检查：

```sh
git status --short
git diff --check
```

同时检查待提交内容中是否误写了本机绝对路径。不要提交本机 IDE、系统或构建输出文件，例如 `.idea/`、`.vscode/`、`.DS_Store`、`.dart_tool/`、`build/`、`coverage/`。

`pubspec.lock` 对 CLI 应用可以提交。发布前需要确认 `pubspec.yaml`、`lib/src/version.dart`、`CHANGELOG.md` 和 `Formula/fluoh.rb` 中的版本信息一致。

## GitHub Actions 与 pub.dev 发布

本仓库通过 GitHub Actions 在收到版本 tag 后发布到 pub.dev：

```sh
git tag v0.0.1
git push origin v0.0.1
```

tag 必须和 `pubspec.yaml` 中的 `version` 对应。pub.dev package admin 需要启用 GitHub Actions automated publishing：

- Repository: `FlutterOH/fluoh`
- Tag pattern: `v{{version}}`
- Environment: `pub.dev`

pub.dev 自动发布只适用于已经存在的 package。第一次发布仍需要维护者手动执行：

```sh
dart pub publish
```

## Homebrew formula

Homebrew formula 位于 [Formula/fluoh.rb](Formula/fluoh.rb)。本地验证：

```sh
brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh
brew install FlutterOH/fluoh/fluoh
fluoh --version
```

正式提供 `brew tap FlutterOH/tap` 时，需要在 FlutterOH 的 tap 仓库中同步 formula。当前 formula 使用 pub.dev archive 作为下载源；版本更新时需要同步 archive URL 和版本号。

## 适配仓库工作流维护

`fluoh create --github --org FlutterOH` 依赖 GitHub CLI：

```sh
gh auth login
```

该命令会创建组织仓库、设置 `origin`，并推送 `main` 与 `ohos-*` 分支。失败时必须保留本地适配仓库，并提示维护者手动创建仓库、设置 remote、推送分支。

`fluoh release` 必须继续保证：

- 只允许在 `ohos-*` 分支运行。
- 当前分支和 `fluoh.yaml` 的 SDK line 一致。
- 工作区干净。
- SDK tag 来自当前数据源。
- release tag 和 manifest 中的 package、上游版本、SDK tag、适配版本一致。
