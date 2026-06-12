# fluoh AI 报告模板（中文）

```md
# fluoh AI 适配报告

- Scope:
- Repository:
- Package:
- Upstream version:
- FlutterOH SDK:
- Date:
- Recommendation: ready | needs maintainer decision | blocked

## Summary / 摘要

- ...

## Adaptation Responsibility / 适配责任边界

- AI 负责自动适配、项目或 Package 改造、命令执行、证据采集、报告生成和发布建议。
- 维护者负责最终发布批准，以及 publish、push、tag、应用商店提交等发布动作。
- `manual-assisted` 表示人工操作了设备或模拟器，但通过/失败必须由工具可读证据确认，不能只写“人工确认通过”，也不能只记录启动状态。

## Changes / 变更

- ...

## Public API / Compatibility / 公共 API / 兼容性

- Public Dart API changes:
- Dependency constraint changes:
- Non-OHOS regression risk:

## Commands / 命令

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `...` | 0 | passed | ... |

## Delivery Checklist / 交付检查清单

- [ ] 已复核 diff；已排除无关文件、本地路径、生成缓存、凭据和私有 token。
- [ ] 命令表包含 exit code，并且证据足以复现判断。
- [ ] OHOS build 证据已记录。
- [ ] OHOS run 证据已记录，或明确记录了缺少设备/模拟器的 blocker。
- [ ] 相关时已记录 Android、iOS、macOS、Linux、Web 和 Windows 回归检查。
- [ ] 交互自动化证据来自已通过的 `flutter test integration_test -d <device>` 命令或真实 `fluoh drive --json`，并且没有未解决的 ready-blocking gate。
- [ ] 权限、文件、相机、定位、媒体、deep link、外部 App 或其他设备流程的功能交互证据已记录。
- [ ] 已复核公共 API、依赖约束和非 OHOS 回归风险。
- [ ] 剩余风险和发布决定已明确。

## Platform Matrix / 平台矩阵

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | skipped | skipped | n/a | n/a | ... |
| Android | not present | not present | n/a | n/a | ... |
| iOS | not present | not present | n/a | n/a | ... |
| macOS | not present | not present | n/a | n/a | ... |
| Linux | not present | not present | n/a | n/a | ... |
| Web | not present | not present | n/a | n/a | ... |
| Windows | not present | not present | n/a | n/a | ... |

## Automation Coverage / 自动化覆盖

从 `fluoh drive --dry-run --json` 或真实 `fluoh drive --json` 中复制完整的
`automation.coveragePolicy.qualityGates` 集合；不要省略当前 Package 中
`notApplicable` 的通用 gate。ready 发布认证不能包含
`needsInventory`、`needsCapabilityCoverageRows`、
`needsPermissionCoverageRows`、`needsPathCoverageReview`、
`needsEvidenceAssertions`、`blocked` 或 `failed` 等未解决状态。
表格前必须记录 `automation.coveragePolicy.status`、`readyForAutomation` 和
`qualityGateSummary`，让交接方能看出覆盖是否可执行、仍缺少行，或正在等待维护者/环境决定。
ready 报告必须显示零个 not-ready gate，例如
`qualityGateSummary: ready=8, notReady=0`。

- coveragePolicy.status: ...
- readyForAutomation: ...
- qualityGateSummary: ...

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | capability inventory reviewed |
| coverage-metadata | readyForReview | every scenario declares coverage metadata or has an explicit no-interaction reason |
| coverage-items | readyForReview | every applicable capability has a coverage row |
| capability-inventory-coverage | readyForReview | all public API/platform/example rows covered or notApplicable |
| scenario-evidence-assertions | readyForReview | scenarios use assertText/waitText/assertLog/assertSession |
| existing-test-baseline | readyForReview | package and integration tests reviewed |
| manifest-permission-coverage | readyForReview | every selected-platform manifest permission is covered or notApplicable |
| behavior-paths | readyForReview | success and negative/error paths are covered or explicitly explained |

## Interaction Evidence / 交互证据

只有当 Package 没有权限、选择器、相机、定位、媒体、deep link、外部 App 或宿主特定行为等
设备侧交互流程时，才使用 `No interaction required: <reason>`。
否则至少写一条具体行。流程已经写在 `integration_test/` 下时使用 `integration_test`；
Commands 表必须记录已通过的 `flutter test integration_test -d <device>` 命令行，
无论该测试是直接运行，还是由 `fluoh run` 触发。
只有在适配期间必须由用户操作设备或模拟器时才使用 `manual-assisted`，并且只有记录了检查内容、
环境、target id、稳定可见状态、日志标记、超出启动状态的有效 session 状态或其他工具可读确认后才能标记 passed。
场景说明应放在 `.fluoh/scenarios/<package-or-scope>/`。

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| `...` | integration_test \| AI-assisted \| manual-assisted | OHOS | device-or-emulator | passed | steps, functional assertions, Flutter debug/widget/semantic/log evidence, flutterRunSession/VM Service evidence when available; screenshots optional |

## Diagnostics / 诊断

- ...

## Fluoh Feedback / fluoh 反馈

把本节替换为 `No fluoh feedback: <reason>`，或填写 `collect_feedback.py`
生成的具体 feedback 行。如果 JSON 包含 `traceError`，也要在这里记录本地 trace 证据问题。

| ID | Owner | Category | Evidence | Proposed fluoh change | Status |
| --- | --- | --- | --- | --- | --- |

## Signing / 签名

- Mode:
- Generated HAPs (build-only when applicable):
- Run session / output log:
- Hilog (drive/debug scenarios only):

## Remaining Risks / 剩余风险

- ...

## Local State / 本地状态

- Git status summary:
- Files intentionally left uncommitted:
- Files that must not be committed:

## Release Decision / 发布决定

Release recommendation: ready | needs maintainer decision | blocked

Reason:
```
