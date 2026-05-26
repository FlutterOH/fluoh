<h1 align="center">
  <img src="docs/assets/svg/fluoh-logo.svg" alt="fluoh logo" width="82" align="absmiddle">
  fluoh
</h1>

<p align="center">
  Bring Flutter apps to OpenHarmony faster.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluoh"><img src="https://img.shields.io/pub/v/fluoh.svg" alt="pub package"></a>
  <a href="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml"><img src="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/FlutterOH/fluoh.svg" alt="License"></a>
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#维护工作流">维护</a> ·
  <a href="docs/commands.zh-CN.md">命令</a> ·
  <a href="docs/schema.zh-CN.md">Schema</a> ·
  <a href="CONTRIBUTING.zh-CN.md">贡献指南</a> ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/assets/svg/readme-hero.svg" alt="fluoh terminal workflow preview" width="900">
</p>

`fluoh` 用来统一 FlutterOH 项目的 SDK 选择、IDE 配置、依赖替换和 Flutter 命令执行。
它会把选中的 SDK 记录到项目中，提供稳定的 IDE SDK 链接，并让终端命令始终使用同一套工具链。

## 快速开始

```sh
dart pub global activate fluoh

cd your_flutter_project
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix
fluoh deps get
fluohf build hap
```

配置完成后，项目会在 `fluoh.yaml` 中记录精确的 SDK 版本，`.fluoh/flutter_sdk`
会作为稳定的 IDE SDK 链接，项目会拥有 `ohos/` 平台目录，FlutterOH 依赖替换来自最新
校验通过的快照。
如果平台目录由其他流程创建，可以使用 `--no-init-ohos` 跳过默认初始化。

## 安装

```sh
dart pub global activate fluoh
fluoh --version
```

确保 Dart pub 的全局可执行目录在 `PATH` 中：

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

macOS 用户也可以通过 Homebrew 安装：

```sh
brew tap FlutterOH/tap
brew install fluoh
```

## 常见工作流

| 场景 | 命令 |
| --- | --- |
| 选择并固定 Flutter OHOS SDK | `fluoh sdk use 3.35 --pub-get` |
| 通过已选择的 SDK 运行 Flutter | `fluohf pub get`, `fluohf run`, `fluohf build hap` |
| 检查 FlutterOH 依赖支持 | `fluoh deps check` |
| 安全改写依赖 | `fluoh deps fix --dry-run`, `fluoh deps fix` |
| 更新已有的 FlutterOH 依赖替换 | `fluoh deps upgrade` |
| 诊断项目配置 | `fluoh doctor` |
| 升级 CLI | `fluoh upgrade` |

### 日常循环

```sh
fluoh sdk list
fluoh sdk use 3.35 --pub-get

fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get

fluohf run
fluohf build hap
```

## 维护工作流

大多数应用项目只需要上面的命令。FlutterOH package 的维护者还可以使用下面的命令创建、
同步、检查和发布第三方库 FlutterOH package 仓库：

```sh
fluoh package create <upstream-git-url>
fluoh package sync
fluoh package status
fluoh package check
fluoh package release
fluoh source sync
```

### AI 辅助

维护者适配第三方 Flutter package 时，先让 `fluoh` 创建仓库契约，再把生成的仓库交给
AI 编码 agent。复制下面这一行，把上游仓库 URL 换成目标 package：

```text
使用 fluoh 将 <upstream-git-url> 适配到 FlutterOH：运行 `fluoh package create <upstream-git-url> --repository <flutteroh-repo-url> --git-author-name "<author-name>" --git-author-email "<author-email>"`，阅读生成的 `AGENTS.md`、`FLUOH.md`、`fluoh.yaml` 和 example，在不改变上游公开 API 的前提下实现 OHOS 平台，运行 `fluoh package check`，更新 `FLUOH_CHANGELOG.md`，并让仓库达到可执行 `fluoh package release` 的状态。
```

生成的 `AGENTS.md` 和 `FLUOH.md` 会给 AI agent 提供稳定的 package 路径、SDK 选择、
检查命令、发布元数据和本地状态规则。发布前仍需要人工 review 最终 diff 和只能在设备上验证的行为。

完整命令见 [docs/commands.zh-CN.md](docs/commands.zh-CN.md)，仓库维护、发布和打包流程见
[CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)。

## Source 数据

`fluoh` 默认使用 FlutterOH 官方 source：

```text
https://github.com/FlutterOH/source.git
```

Source 是 fluoh 用来发现 Flutter OHOS SDK 版本和 package 兼容性记录的数据源。
大多数应用项目只需要运行 `fluoh source update`。

Source 元数据和兼容性 schema 的细节见
[docs/schema.zh-CN.md](docs/schema.zh-CN.md)。

## 许可证

MIT
