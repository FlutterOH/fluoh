<h1 align="center">
  <img src="doc/assets/svg/fluoh-logo.svg" alt="fluoh logo" align="absmiddle">
  fluoh
</h1>

<p align="center">
  用 AI 将 Flutter App 和 Package 适配到 OHOS。
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
  <img src="doc/assets/svg/readme-hero.zh-CN.svg" alt="fluoh AI 适配提示预览">
</p>

## 快速开始

### AI 优先

适配 App 或 Package 时，可以优先使用 fluoh AI skill。它会先确认适配范围，
再完成代码调整、运行验证，并生成本地报告。

在 AI agent 中安装内置 skill：

```text
从 https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 安装 fluoh skill，如果已存在则覆盖安装。
```

然后按 App 或 Package 场景输入一句话：

```text
使用 $fluoh，必要时先安装 fluoh，然后把当前 Flutter 项目适配到 OHOS。
使用 $fluoh，把 <upstream-git-url> 适配为 FlutterOH Package。
使用 $fluoh，继续适配 <package-name> 到 OHOS。
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

先发现 upstream 包，再创建 FlutterOH 适配仓库：

```sh
fluoh package discover <upstream-git-url>
fluoh package create <upstream-git-url> --repository-name <flutteroh-repo-name>
cd <flutteroh-repo-name>
fluoh verify --package <name>
fluoh run ohos --package <name> --auto-emulator
fluoh attach ohos --session-file <session-file>
fluoh package status --package <name>
```

`fluoh attach` 会复用 Flutter run session，优先连接 VM Service URI；如果
session 没有提供 URI，则退回使用目标设备 id。

需要时，在生成仓库中追加另一个 Package 分支：

```sh
fluoh package queue <package-path>...
fluoh package add <package-path>
fluoh verify --package <name>
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
