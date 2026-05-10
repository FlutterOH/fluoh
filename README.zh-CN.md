# fluoh

FlutterOH 生态命令行工具，用于管理 Flutter OHOS SDK、检查项目依赖适配状态，并辅助第三方库维护者创建 FlutterOH pub 仓库。

[English](README.md) | [贡献指南](CONTRIBUTING.zh-CN.md)

## 为什么需要 fluoh

FlutterOH 项目通常会同时遇到三类问题：SDK 版本需要和项目绑定，pub 依赖需要确认是否已有 OHOS 适配，第三方库 pub 仓库需要统一命名、分支和发布规则。`fluoh` 把这些流程收敛成一组可重复执行的 CLI 命令。

主要能力：

- 通过 `fluoh.yaml` 安装、缓存、切换并运行 Flutter OHOS SDK。
- 根据 FlutterOH 数据源检查依赖兼容性，生成 OHOS 适配依赖替换。
- 初始化第三方 package 的 FlutterOH pub 仓库，生成 OHOS 分支和 release tag。
- 支持 pub 仓库 remote 配置和 Homebrew 安装链路。

## 安装

推荐使用 Dart 全局激活：

```sh
dart pub global activate fluoh
fluoh --version
```

确保 Dart pub 的全局可执行目录在 `PATH` 中。macOS 和 Linux 通常是：

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

macOS 用户也可以通过 Homebrew 安装：

```sh
brew tap FlutterOH/tap
brew install fluoh
```

## 快速开始

在 Flutter 项目根目录执行：

```sh
fluoh source update
fluoh sdk list
fluoh sdk use 3.35
fluoh pub get
fluoh pub check
fluoh pub fix
fluoh pub get
fluoh doctor
```

`fluoh sdk use` 支持精确 SDK tag，也支持 `3.35` 这样的版本系列；版本系列会解析到该系列最新 stable SDK，把精确 tag 写入 `fluoh.yaml`，并更新 `.fluoh/flutter_sdk` 作为稳定的 IDE SDK 路径。之后用 `fluoh flutter ...` 或快捷可执行入口 `fluohf ...` 执行项目 Flutter 命令，例如 `fluohf pub get`、`fluohf run` 或 `fluohf build hap`。这些命令会从当前目录向上使用最近的 `fluoh.yaml`，因此生成的测试目录会继承项目 SDK，monorepo 的子项目也可以分别选择 SDK。如果希望切换 SDK 后立即执行首次 `pub get`，可以给 `fluoh sdk use` 加上 `--pub-get`。

使用 `fluoh pub get` 可以通过已选择的 SDK 解析依赖。在适配仓库中，它也会为生成的 `fluoh_test` 工作区执行 `pub get`，包括 `fluoh_test/some_package` 这样的 monorepo 包级工作区及其 `example` app。

使用 `fluoh clean` 可以在当前项目中执行 `fluoh flutter clean`，并清理生成的 `fluoh_test` 构建产物。它不会删除已缓存的 SDK 或数据源。

## 常见工作流

### 切换 Flutter OHOS SDK

从 `fluoh sdk list` 中选择版本系列或精确 SDK tag：

```sh
fluoh sdk list
fluoh sdk use 3.35
fluoh flutter --version
```

### 检查并修复 OHOS 依赖适配

```sh
fluoh pub check
fluoh pub fix
fluoh pub get
```

`fluoh pub check` 会按兼容状态分组依赖并提示下一步。`fluoh pub fix` 会把推荐的 OHOS adapter ref 写入 `pubspec.yaml`；如果只想预览，使用 `fluoh pub fix --dry-run`。默认写入 `dependency_overrides`；如果希望直接改写 `dependencies` 中的声明，在 `fluoh.yaml` 中设置 `dependencyPolicy.replacementMode: rewrite`。精确匹配和 pub-semver 兼容的 adapter 升级会默认应用；不兼容的版本变化和降级默认跳过，除非把 `dependencyPolicy.versionMismatch` 设为 `allow`。项目已经使用 OHOS adapter、只想刷新已有 ref 时，使用 `fluoh pub upgrade`。

### 创建第三方库 pub 仓库

```sh
fluoh pub create https://github.com/upstream/package.git --sdk 3.35.8-ohos-0.0.3
git commit -m "feat(pub): initialize FlutterOH adapter"
fluoh pub sync
fluoh pub release --push
```

monorepo package 可以指定包路径：

```sh
fluoh pub create https://github.com/upstream/monorepo.git \
  --path packages/some_package \
  --sdk 3.35.8-ohos-0.0.3
```

同一个 monorepo 中需要适配多个包时，可以重复传 `--path`，也可以之后在 adapter 仓库中继续添加：

```sh
fluoh pub create https://github.com/upstream/monorepo.git \
  --path packages/package_a \
  --path packages/package_b
fluoh pub add --path packages/package_c
```

默认生成的 pub 仓库会保持上游默认分支干净，把源仓库保留为 `upstream`，创建 `ohos/<sdk-series>` 分支，例如 `ohos/3.35`，设置 `origin`，并写入 FlutterOH 元数据、适配指南、`FLUOH_CHANGELOG.md` release notes、AI agent 指令，以及 Flutter package/plugin 的 `fluoh_test/` 工作区。monorepo 子库会使用 `fluoh_test/<package>/`，让每个 package 都有独立的自动化测试和人工验证 example。`fluoh pub create` 和 `fluoh pub add` 会暂存生成文件，但不会创建提交。运行 `pub sync` 或 `pub release` 前需要先提交。`fluoh pub sync` 会快进同步上游分支，把它合入当前 pub 分支，并且只刷新 `fluoh.yaml` 中的 upstream 元数据；新的 FlutterOH package version 应在适配完成后再更新。

`fluoh test init` 会为单包 adapter 创建 `fluoh_test/test` 自动化检查和 `fluoh_test/example` app；monorepo 子库使用 `fluoh test init --package <name>` 和 `fluoh_test/<name>/`。`fluoh test run` 会先在存在 `test/**/*_test.dart` 时运行适配库自身的 Flutter 测试，等价于在 package 路径执行 `fluoh flutter test`，再运行匹配的 `fluoh_test` 工作区。`fluoh pub release --package <name>` 发布单个 package；`fluoh pub release --all` 会先校验并测试所有已注册 package，全部通过后再分别创建 release tag。FlutterOH/pub 数据源元数据更新应通过 PR，或等待定时数据源拉取流程处理。

如果需要指定最终推送位置：

```sh
fluoh pub create https://github.com/upstream/package.git \
  --sdk 3.35.8-ohos-0.0.3 \
  --repo git@github.com:FlutterOH/package.git
```

## 命令概览

| 命令 | 用途 |
| --- | --- |
| `fluoh flutter ...` / `fluohf ...` | 使用最近的 `fluoh.yaml` 中选择的 SDK 运行 `flutter`；FlutterOH 项目中的日常 Flutter 命令优先走这个入口。 |
| `fluoh clean` | 通过已选择的 SDK 执行 `flutter clean`，并删除生成的 `fluoh_test` 产物。 |
| `fluoh sdk ...` | 查看、安装、删除并选择本地 Flutter OHOS SDK。 |
| `fluoh sdk use <version-or-series>` | 在当前 Flutter 项目中切换 SDK，并更新给 IDE 使用的 `.fluoh/flutter_sdk`。 |
| `fluoh pub get` | 通过已选择的 SDK 为当前项目和 `fluoh_test` 工作区执行 `flutter pub get`。 |
| `fluoh pub check` | 检查项目依赖的 OHOS 兼容状态。 |
| `fluoh pub fix` | 在 `pubspec.yaml` 中新增缺失的 OHOS adapter ref，并刷新已有 ref。 |
| `fluoh pub upgrade` | 只升级已有 OHOS adapter ref，不新增依赖替换。 |
| `fluoh pub create/add/sync/release` | 创建、扩展、同步并发布第三方库 FlutterOH pub 仓库。 |
| `fluoh test ...` | 为已适配 Flutter package 创建 `fluoh_test`，并运行库自身和 `fluoh_test` 验证。 |
| `fluoh source ...` | 管理 FlutterOH 数据源。 |
| `fluoh doctor` | 诊断 CLI 版本、项目 SDK 和 OHOS 目录状态。 |
| `fluoh upgrade` | 升级 `fluoh` CLI 工具本身。 |

`fluoh pub upgrade` 和 `fluoh upgrade` 的语义不同：前者刷新当前项目已有 OHOS adapter ref，后者升级 CLI 工具本身。

## 数据源

`fluoh` 默认使用 FlutterOH 官方数据源：

```text
https://github.com/FlutterOH/pub.git
```

也可以创建本地数据源，或接入团队内部数据源：

```sh
fluoh source init ./flutteroh-pub-local
fluoh source add local ./flutteroh-pub-local --priority 200
fluoh source add internal https://github.com/example/flutteroh-pub.git --priority 200
fluoh source update
```

`fluoh source init` 会创建一个兼容 `FlutterOH/pub` 的 package-only 数据源模板。数据源会按 priority 叠加使用；团队内部源或本地源可以只提供 `packages/repositories.yaml` 和 `packages/manifests/*.yaml` 来补充自有适配库，SDK 列表继续来自官方源。除了官方源 `flutteroh` 外，其他源都可以移除：

```sh
fluoh source remove internal
```

远端源和本地源都会以最新校验通过的快照缓存到 `FLUOH_HOME` 下；`fluoh` 不会在数据源缓存中保留 Git 历史。

## 贡献

本地开发、测试、发布到 pub.dev、Homebrew formula 维护和提交前检查见 [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)。

## License

MIT
