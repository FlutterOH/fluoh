# Contributing to fluoh

English: [CONTRIBUTING.md](CONTRIBUTING.md)

本文档面向 `fluoh` 的贡献者和维护者。普通用户优先阅读 [README.zh-CN.md](README.zh-CN.md) 或 [README.md](README.md)。

## 本地开发

在仓库根目录安装依赖并运行 CLI：

```sh
dart pub get
dart run bin/fluoh.dart --help
dart run bin/fluoh.dart --version
```

调试项目级 Flutter 命令时，进入一个 Flutter 项目并先选择 SDK：

```sh
dart /path/to/fluoh/bin/fluoh.dart sdk use 3.35
dart /path/to/fluoh/bin/fluoh.dart flutter --version
```

项目级 Flutter 命令需要先用 `fluoh sdk use <version-or-series>` 选择项目
SDK，然后通过 `fluoh flutter ...` 执行，避免本地调试依赖全局 `flutter` 当前指向哪个 SDK。

如果需要直接调用安装后的 `fluoh` 命令名，可以把当前源码全局激活为本地 path 包：

```sh
dart pub global activate --source path . --overwrite
fluoh --version
```

如果 shell 提示找不到 `fluoh`，把 Dart pub 的全局可执行目录加入 `PATH`：

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

普通代码修改通常不需要重新激活，除非调整了 executable 或 package 元数据。调试已发布版本时，激活 hosted 包：

```sh
dart pub global activate fluoh --overwrite
dart pub global activate fluoh 0.1.0 --overwrite
fluoh --version
```

调试完成后，用 `dart pub global activate --source path . --overwrite` 切回本地源码版本，或卸载全局激活的 `fluoh`：

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

`dart format .` 运行后不应留下未确认的格式化 diff。GitHub Actions 会在 push 到 `main`、版本 tag 和 pull request 时执行同等检查；pub.dev 发布 workflow 必须通过：

- `dart format --output=none --set-exit-if-changed .`
- `dart analyze`
- `dart test`

发布前还需要运行：

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

同时检查待提交内容中是否误写本机绝对路径。不要提交 IDE、系统或构建输出文件，例如 `.idea/`、`.vscode/`、`.DS_Store`、`.dart_tool/`、`build/`、`coverage/`。

`pubspec.lock` 对 CLI 应用可以提交。发布前需要确认 `pubspec.yaml`、`lib/src/version.dart`、`CHANGELOG.md` 和 `Formula/fluoh.rb` 中的版本信息一致。

## Commit 格式

提交信息使用 Conventional Commits：

```text
<type>(<scope>): <subject>
```

`scope` 可选，建议使用受影响的命令、模块或文档范围，例如 `sdk`、`pub`、`source`、`docs`、`ci`。

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
feat(pub): configure pub repository remotes
fix(pub): upgrade rewritten OHOS dependencies
docs: add Homebrew installation guide
ci: publish package on version tags
```

提交标题使用简短英文描述，首行不超过 72 个字符。需要说明背景、风险或验证方式时，再补充正文。

## GitHub Actions 与 pub.dev 发布

本仓库通过 GitHub Actions 在收到版本 tag 后发布到 pub.dev：

```sh
git tag v0.1.0
git push origin v0.1.0
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
brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git
brew install FlutterOH/fluoh/fluoh
fluoh --version
```

正式提供 `brew tap FlutterOH/tap` 时，需要在 FlutterOH 的 tap 仓库中同步 formula。当前 formula 使用 pub.dev archive 作为下载源；版本更新时需要同步 archive URL 和版本号。

## Pub 仓库工作流维护

`fluoh pub create` 会保持上游分支干净，把克隆来源保留为 `upstream`，创建 `ohos/3.35` 这类 Flutter OHOS SDK line 分支，把 `origin` 设置为 pub 仓库最终推送位置，并配置所选 Flutter OHOS SDK 环境。默认仓库 URL 会根据 package 名称推导：

```sh
git@github.com:FlutterOH/<package>.git
```

如果某个 package 需要推送到独立 FlutterOH pub 仓库，创建时使用 `--repo` 指定：

```sh
fluoh pub create https://github.com/upstream/package.git \
  --sdk 3.35.8-ohos-0.0.3 \
  --repo git@github.com:FlutterOH/package.git
```

该命令只配置本地 remote，不创建远端仓库，也不依赖 GitHub CLI，因为上游 package 不一定托管在 GitHub。维护者需要先确保目标远端仓库存在，再手动 push 分支或 release tag。

`fluoh pub create` 会暂存生成的 `AGENTS.md`、`FLUOH.md`、`FLUOH_CHANGELOG.md`、`fluoh.yaml`，以及 Flutter package/plugin 的 `fluoh_test/`，但不会创建初始提交。维护者可以继续完成 FlutterOH 适配，最后用维护者自己的 Git 身份一起提交。运行任何要求干净工作区的命令前需要先提交：

```sh
git commit -m "feat(pub): initialize FlutterOH package"
```

使用 `fluoh pub sync` 从 `upstream` 快进同步 Package `fluoh.yaml` 记录的上游分支，把该分支合入当前 `ohos/<sdkLine>` 分支，并且只刷新 `fluoh.yaml` 中的 upstream 元数据。新的 FlutterOH 适配完成前保持 upstream package version 不变。

`fluoh_test/test` 用于发布前必须通过的自动化平台适配检查，`fluoh_test/example` 是小型人工验证 app。`fluoh test run` 会在存在 `test/**/*_test.dart` 时先运行 package 自身的 Flutter 测试，等价于在 package 路径执行 `fluoh flutter test`，再使用当前选择的 Flutter OHOS SDK 执行 `fluoh_test` 自动化检查。

`fluoh pub release` 必须继续保证：

- 当前分支和 `fluoh.yaml` 记录的 `repository.git.branch` 分支一致。
- 工作区干净。
- SDK version 来自已配置的数据源。
- Package `version` 大于同 package、上游版本、SDK line 下已有 release tag 的版本。
- 缺失或未填写当前版本的 `FLUOH_CHANGELOG.md` release notes 会提示 warning，但不阻塞 release。
- Flutter package 自身测试和 `fluoh_test` 通过 `fluoh test run`。
- release tag 和 Package `fluoh.yaml` 中的 package、上游版本、SDK line、`version` 一致。

FlutterOH pub 仓库的 release 命令不得直接写入 source 元数据。发布记录通过 `fluoh source sync` 从已发布 pub 仓库生成；路由、advisory 和 maintenance 元数据直接编辑 Source 和 Manifest YAML。已发布 FlutterOH package 应通过 FlutterOH/pub PR 注册，PR 和定时 package 拉取流程都应调用同一套 source 命令路径。
