# fluoh

<p align="center">
  <strong>让 FlutterOH 项目配置变得无聊。</strong>
</p>

<p align="center">
  选 SDK，修 FlutterOH 依赖替换，再用正确的工具链运行 Flutter。
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluoh"><img src="https://img.shields.io/pub/v/fluoh.svg" alt="pub package"></a>
  <a href="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml"><img src="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/FlutterOH/fluoh.svg" alt="License"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="docs/commands.zh-CN.md">命令设计</a> ·
  <a href="docs/schema.zh-CN.md">Schema 设计</a> ·
  <a href="CONTRIBUTING.zh-CN.md">贡献指南</a>
</p>

`fluoh` 是 FlutterOH 项目的控制入口。它记录项目应该使用的 Flutter OHOS SDK
version，通过该 SDK 运行 Flutter，检查 pub 依赖是否已有 FlutterOH 适配，并替你应用安全的
`pubspec.yaml` 修改。

```sh
dart pub global activate fluoh

cd your_flutter_project
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh pub check
fluoh pub fix
fluohf build hap
```

执行后，项目会在 `fluoh.yaml` 中记录精确 SDK version，`.fluoh/flutter_sdk` 会成为稳定的
IDE SDK 路径，FlutterOH 依赖替换也会匹配 FlutterOH 官方 source 的最新校验通过的快照。

## 为什么需要它

FlutterOH 项目不应该靠本地 checklist 维持：

- 这个项目到底用哪个 Flutter OHOS SDK checkout？
- IDE 和终端是否指向同一个 SDK？
- 这些 pub 依赖有没有 FlutterOH 适配？
- FlutterOH 依赖替换是最新的，还是从旧项目复制来的？

`fluoh` 把这些答案变成项目状态和可重复执行的命令。

## 日常循环

```sh
# 每个项目选择一次 SDK。
fluoh sdk list
fluoh sdk use 3.35 --pub-get

# 通过已选择的 SDK 运行 Flutter。
fluohf pub get
fluohf run
fluohf build hap

# 维护 FlutterOH 依赖替换。
fluoh pub check
fluoh pub fix --dry-run
fluoh pub fix
fluoh pub get
```

常用补充命令：

```sh
fluoh pub upgrade   # 只升级已有 FlutterOH 依赖替换
fluoh clean         # 执行 flutter clean 并清理生成的 fluoh_test 输出
fluoh doctor        # 诊断 source、SDK 选择和项目配置
fluoh upgrade       # 升级 fluoh CLI
```

`fluoh pub fix` 默认写入 `dependency_overrides`。如果项目要直接改写
`dependencies`，在 `fluoh.yaml` 中设置 `dependencyPolicy.pubspecSection: dependencies`。
不兼容版本变化和降级默认跳过，除非 `dependencyPolicy.versionChanges` 是 `any`。

## 安装

```sh
dart pub global activate fluoh
fluoh --version
```

确保 Dart pub 的全局可执行目录在 `PATH` 中：

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

macOS 上也可以使用 Homebrew：

```sh
brew tap FlutterOH/tap
brew install fluoh
```

## 维护者入口

大多数用户只需要上面的项目命令。维护者还可以使用第三方库 FlutterOH pub 仓库和 source
元数据工作流：

```sh
fluoh pub create
fluoh pub sync
fluoh test init
fluoh test run
fluoh pub release
fluoh source sync
```

完整命令见 [docs/commands.zh-CN.md](docs/commands.zh-CN.md)，仓库、发布和打包流程见
[CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)。

## Source 数据

`fluoh` 默认使用 FlutterOH 官方 source：

```text
https://github.com/FlutterOH/pub.git
```

`fluoh source update` 会把最新校验通过的快照刷新到 `FLUOH_HOME` 下。source 文件细节见
[docs/schema.zh-CN.md](docs/schema.zh-CN.md)。

## License

MIT
