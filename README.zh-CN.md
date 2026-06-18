<h1 align="center">
  <img src="doc/assets/svg/fluoh-logo.svg" alt="fluoh logo" align="absmiddle">
  fluoh
</h1>

<p align="center">
  面向 Flutter App 和 Package 的 FlutterOH 优先 AI 工作流。
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluoh"><img src="https://img.shields.io/pub/v/fluoh.svg" alt="pub package"></a>
  <a href="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml"><img src="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="skills/fluoh/SKILL.md"><img src="https://img.shields.io/badge/AI%20skill-skills%2Ffluoh-6f42c1" alt="AI skill"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/FlutterOH/fluoh.svg" alt="License"></a>
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="skills/fluoh/SKILL.md">Skill</a> ·
  <a href="doc/commands.zh-CN.md">命令</a> ·
  <a href="doc/schema.zh-CN.md">Schema</a> ·
  <a href="CONTRIBUTING.zh-CN.md">贡献指南</a> ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="doc/assets/svg/readme-hero.zh-CN.svg" alt="fluoh AI 支持提示预览">
</p>

## 快速开始

### AI 优先

为 App 或 Package 增加 FlutterOH 支持时，可以优先使用 fluoh AI skill。它会先确认支持范围，
再完成代码调整、运行目标平台和保留平台验证，并生成本地报告。

在 AI agent 中安装内置 skill：

```text
运行 `fluoh skill --path`，把打印的路径安装为 fluoh skill，并覆盖已有安装。仅在尚未安装 fluoh 时，才使用 https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 作为初始来源。
```

然后按 App 或 Package 场景输入一句话：

```text
使用 $fluoh，必要时先安装 fluoh，然后为当前 Flutter 项目增加 FlutterOH 支持。
使用 $fluoh，将 <upstream-git-url> 移植为 FlutterOH Package。
使用 $fluoh，继续为 <package-name> 实现 FlutterOH 支持。
使用 $fluoh，预检查这个 FlutterOH Source 变更。
```

AI 流程见 [skill](skills/fluoh/SKILL.md)；CLI 行为见
[命令参考](doc/commands.zh-CN.md)。

### 安装 fluoh

```sh
dart pub global activate fluoh
```

macOS 也可以使用原生命令安装：

```sh
brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git
brew install FlutterOH/fluoh/fluoh
```

### 已有 Flutter App

在项目根目录执行：

```sh
cd path/to/existing_app
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project
fluoh build ohos --auto-sign
```

先检查 `fluoh deps fix --dry-run` 输出，再执行 `fluoh deps fix`。

### 新建 Flutter App

先用 FlutterOH SDK 创建项目：

```sh
fluoh create --sdk 3.35 demo_app --platforms=android,ios,ohos
cd demo_app
```

然后执行已有 App 部分从 `fluoh deps check` 开始的命令。

### Package 维护者

可以先基于 spec 新建 FlutterOH Package 仓库，也可以发现并移植 upstream Package 仓库：

```sh
fluoh package new <name> --repository-name <flutteroh-repo-name>
fluoh package discover <upstream-git-url>
fluoh package port <upstream-git-url> --repository-name <flutteroh-repo-name>
cd <flutteroh-repo-name>
fluoh package next --package <name>
fluoh package status --package <name>
```

`fluoh package next` 每次只输出一个聚焦的实现动作。按打印的动作执行并重复
运行，直到 ready 或 blocked，再用 `package status`、`package handoff` 和
`package check` 检查发布就绪状态。

需要时，在生成仓库中追加另一个 Package 分支：

```sh
fluoh package queue <package-path>...
fluoh package add <package-path>
fluoh verify --package <name>
```

首次发布后，把 Package 分支注册到 Source：

```sh
fluoh source register . --source <source-repo>
```

使用已选择的 FlutterOH SDK 执行 Flutter 命令：

```sh
fluohf pub get
fluohf run
fluohf build hap
```

## 链接

- [命令参考](doc/commands.zh-CN.md)
- [Source schema](doc/schema.zh-CN.md)
- [贡献和发布流程](CONTRIBUTING.zh-CN.md)
- [官方 source 数据](https://github.com/FlutterOH/source.git)

## 许可证

MIT
