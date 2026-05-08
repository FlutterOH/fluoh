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
fluoh flutter pub get
fluoh deps check
fluoh deps fix --yes
fluoh doctor
```

`fluoh sdk use` 支持精确 SDK tag，也支持 `3.35` 这样的版本系列；版本系列会解析到该系列最新 stable SDK，并把精确 tag 写入 `fluoh.yaml`。之后用 `fluoh flutter ...` 执行项目 Flutter 命令，例如 `fluoh flutter pub get`、`fluoh flutter run` 或 `fluoh flutter build hap`。如果希望切换 SDK 后立即执行首次 `pub get`，可以给 `fluoh sdk use` 加上 `--pub-get`。

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
fluoh deps check
fluoh deps fix --yes
fluoh deps update --yes
```

`fluoh deps fix` 默认写入 `dependency_overrides`。如果需要直接改写 `dependencies` 中的声明，可以使用 `--rewrite`。

### 创建第三方库 pub 仓库

```sh
fluoh pub create https://github.com/upstream/package.git --sdk 3.35.8-ohos-0.0.3
git commit -m "feat(pub): initialize FlutterOH adapter"
fluoh pub sync
fluoh pub adapt
fluoh pub release --push
```

monorepo package 可以指定包路径：

```sh
fluoh pub create https://github.com/upstream/monorepo.git \
  --package some_package \
  --path packages/some_package \
  --sdk 3.35.8-ohos-0.0.3
```

默认生成的 pub 仓库会保持上游默认分支干净，把源仓库保留为 `upstream`，创建 `ohos/<sdk-series>` 分支，例如 `ohos/3.35`，设置 `origin`，并写入 FlutterOH 元数据、适配指南和 AI agent 指令。`fluoh pub create` 会暂存生成文件，但不会创建提交。运行 `pub sync`、`pub adapt` 或 `pub release` 前需要先提交。

`fluoh pub release` 只负责校验适配库并创建或推送 release tag。FlutterOH/pub 数据源元数据更新应通过 PR，或等待定时数据源拉取流程处理。

如果需要指定最终推送位置：

```sh
fluoh pub create https://github.com/upstream/package.git \
  --sdk 3.35.8-ohos-0.0.3 \
  --repo git@github.com:FlutterOH/package.git
```

## 命令概览

| 命令 | 用途 |
| --- | --- |
| `fluoh flutter ...` | 使用 `fluoh.yaml` 中选择的 SDK 运行 `flutter`；FlutterOH 项目中的日常 Flutter 命令优先走这个入口。 |
| `fluoh sdk ...` | 查看、安装、删除并选择本地 Flutter OHOS SDK。 |
| `fluoh sdk use <version-or-series>` | 在当前 Flutter 项目中切换 SDK。 |
| `fluoh deps check` | 检查项目依赖的 OHOS 兼容状态。 |
| `fluoh deps fix` | 写入适配依赖替换。 |
| `fluoh deps update` | 升级项目内已有 OHOS 适配依赖版本。 |
| `fluoh pub ...` | 创建、同步、适配并发布第三方库 FlutterOH pub 仓库。 |
| `fluoh source ...` | 管理 FlutterOH 数据源。 |
| `fluoh doctor` | 诊断 CLI 版本、项目 SDK 和 OHOS 目录状态。 |
| `fluoh upgrade` | 升级 `fluoh` CLI 工具本身。 |

`fluoh deps update` 和 `fluoh upgrade` 的语义不同：前者更新当前项目内已兼容 OHOS 的第三方库版本，后者升级 CLI 工具本身。

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
