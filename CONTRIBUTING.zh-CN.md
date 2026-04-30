# Contributing to fluoh

English: [CONTRIBUTING.md](CONTRIBUTING.md)

本文档面向 `fluoh` 的贡献者和维护者。普通用户优先阅读 [README.zh-CN.md](README.zh-CN.md) 或 [README.md](README.md)。

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

如果需要像用户安装后一样直接调用 `fluoh` 命令调试，可以从仓库根目录把当前源码全局激活为本地 path 包：

```sh
dart pub global activate --source path . --overwrite
fluoh --version
```

如果 shell 提示找不到 `fluoh`，确认 Dart pub 的全局可执行目录已经加入 `PATH`：

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

之后 shell 中的 `fluoh` 会指向当前仓库源码。修改代码后通常不需要重新激活；如果调整了 executable 或 package 元数据，再重新运行上面的 `dart pub global activate` 命令。

如果需要调试 pub.dev 上已经发布的版本，可以激活 hosted 包：

```sh
dart pub global activate fluoh --overwrite
fluoh --version
```

调试指定已发布版本时，在包名后添加版本号：

```sh
dart pub global activate fluoh 0.0.1 --overwrite
fluoh --version
```

调试完成后，可以用 `dart pub global activate --source path . --overwrite` 切回本地源码版本，或卸载全局激活的 `fluoh`：

```sh
dart pub global deactivate fluoh
```

如果需要隔离本地配置和缓存，可以设置 `FLUOH_HOME`：

```sh
FLUOH_HOME=/path/to/cache dart run bin/fluoh.dart source list
```

## 验证

提交前必须运行并通过：

```sh
dart format .
dart analyze
dart test
```

`dart format .` 运行后不应留下未确认的格式化 diff；如果产生变更，需要一起检查并提交。`dart analyze` 和 `dart test` 必须通过后再提交。

GitHub Actions 会在 push 到 `main`、版本 tag 和 pull request 时执行同等检查；pub.dev 发布 workflow 也必须先通过这些检查再发布：

- `dart format --output=none --set-exit-if-changed .`
- `dart analyze`
- `dart test`

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

## Commit 格式

提交信息使用 Conventional Commits：

```text
<type>(<scope>): <subject>
```

`scope` 可选，建议使用受影响的命令、模块或文档范围，例如 `sdk`、`deps`、`adapter`、`source`、`docs`、`ci`。

常用 `type`：

- `feat`: 新功能或新命令。
- `fix`: bug 修复。
- `docs`: 文档变更。
- `test`: 测试新增或调整。
- `refactor`: 不改变行为的代码重构。
- `chore`: 构建、依赖、版本、仓库维护等杂项。
- `ci`: GitHub Actions 或发布流水线变更。

示例：

```text
feat(adapter): configure adapter repository remotes
fix(deps): update rewritten OHOS dependencies
docs: add Homebrew installation guide
ci: publish package on version tags
```

提交标题使用英文祈使句或简短描述，首行不超过 72 个字符。需要说明背景、风险或验证方式时，在空行后补充正文。

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

`fluoh create` 会把克隆来源保留为 `upstream`，并把 `origin` 设置为适配仓库最终推送位置。默认值是：

```sh
git@github.com:FlutterOH/fluoh.git
```

如果某个适配库需要推送到独立仓库，创建时使用 `--repository` 指定：

```sh
fluoh create https://github.com/upstream/package.git \
  --sdk-line 3.22 \
  --repository git@github.com:FlutterOH/package.git
```

该命令只配置本地 remote，不创建远端仓库，也不依赖 GitHub CLI。维护者需要先确保目标远端仓库存在，再手动 push 分支或 release tag。

`fluoh release` 必须继续保证：

- 只允许在 `ohos-*` 分支运行。
- 当前分支和 `fluoh.yaml` 的 SDK line 一致。
- 工作区干净。
- SDK tag 来自已配置的数据源。
- release tag 和 manifest 中的 package、上游版本、SDK tag、适配版本一致。
