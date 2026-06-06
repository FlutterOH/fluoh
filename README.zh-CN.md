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
  <img src="https://img.shields.io/badge/diagnostics-JSON-blue" alt="JSON diagnostics">
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

先让 AI agent 安装 skill：

```text
从 https://github.com/FlutterOH/fluoh/tree/main/skills 安装 fluoh skill。
```

然后按 App 或 Package 场景输入一句话：

```text
使用 $fluoh，必要时先安装 fluoh，然后把当前 Flutter 项目适配到 OHOS。
使用 $fluoh，把 <upstream-git-url> 适配为 FlutterOH Package。
使用 $fluoh，继续适配 <package-name> 到 OHOS。
```

skill 会先检查 `fluoh --version`，运行只读 setup 检查，并在修改 App 或 Package 前请求
最终 setup 确认；之后跟随 JSON diagnostics，修改并验证目标，最后保存
`.fluoh/reports/<scope>/ai-report-...md`。安装 CLI 时优先使用
`dart pub global activate fluoh`，macOS 下可退到 Homebrew。trace、报告目录和 Package
仓库细节见命令文档和 skill 文档。

如果已经安装了 CLI：

```text
运行 `fluoh skill --json`，把返回的 localPath 安装为 skill，必要时重载 skills。
```

skill 版本跟随 `fluoh` CLI 版本。运行 `fluoh upgrade` 后，重新执行
`fluoh skill --json` 并重载返回的路径。

## 手动兜底

需要自己安装或驱动 CLI 时：

```sh
dart pub global activate fluoh
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix
fluoh doctor -p --platform ohos
fluoh build --platform ohos --auto-sign
```

macOS 也可以用 Homebrew：

```sh
brew tap FlutterOH/tap
brew install fluoh
```

Homebrew 会安装 native 可执行文件，更适合严格 `--json` 自动化。

Package 维护者可以用：

```sh
fluoh package create <upstream-git-url> --repository-name <flutteroh-repo-name>
fluoh verify
fluoh package status
```

适配 monorepo 时，一个 upstream 仓库保留一份 FlutterOH 适配仓库，每个 Package 使用独立的
`ohos/<sdkLine>/<package>` 分支。先用 `--package-path` 创建第一个分支，再用
`fluoh package queue` 和 `fluoh package add` 追加其他 Package。版本、报告和 `--org`
细节见 [命令参考](doc/commands.zh-CN.md)。

用 `fluohf` 通过已选择的 FlutterOH SDK 运行 Flutter：

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
