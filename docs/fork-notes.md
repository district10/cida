# 这个 fork：把辞达当"收集器"用

这是一份**个人 fork**，分支 `notes`。上游是 [Xuanwo/cida](https://github.com/Xuanwo/cida)（辞达：用你自己的模型在 Mac 任何地方翻译和润色）。
我们保留它的全部翻译能力，只加一件事：**把选中的文字（或剪贴板里的文字）一键存成本地笔记**。

## 一、为什么做这份 fork

上游辞达把"翻译与润色"打磨得很细：选区读取有辅助功能优先 + ⌘C 兜底 + 剪贴板原样放回 + 密码框拒绝 + Dvorak 键位匹配，
还有提示胶囊、权限引导、日志与测试。这些正是自己另起一个收集器最容易做糙的部分。

所以我们不另写工具，只在这份 fork 上做一件事：**把选中的文字（或剪贴板里的文字）一键存成本地笔记**。
辞达负责划词与剪贴板，翻译能力一个不动；笔记落在辞达自己的收件箱里（§三）。

## 二、我们加了什么

| 能力 | 入口 | 说明 |
| --- | --- | --- |
| 划词存笔记 | **⌥N** | 读选中文字（与 ⌥A 同一条读数路径），追一行，提示胶囊「已存入笔记 · Safari」；不弹面板、不请求模型、不动焦点、不动剪贴板 |
| 剪贴板存笔记 | **⌥N**（没选中时） | 剪贴板里有文本就存它，`source` 记 `"clipboard"`；一次按键覆盖"选中了/刚复制了"两种场合 |
| 看完再存 | **⌥A** 开面板 → **⌘S**（或面板打开时按 ⌥N） | 存的是面板里那段文字（可编辑、可粘贴、可用 ⌥S 截图识别），`app` 记唤起面板时所在的应用 |
| 翻译/改写自动入库 | 无需按键，默认开 | 每次生成成功后自动追一行：原文在 `text`，译文/改写结果在 `note`，`source` 记 `translation`/`improvement`；面板的翻译与改进、⌥F 的改进并替换都算，⌥D 原处翻译不算（一次一屏，太吵） |
| 快速问答 | **⌥C** | 弹出一个小窗问一句、接着追问（模型是设置里那一个，system 提示词可在设置里改）；每答完一轮追一行，`source` 记 `chat`，`text` 是**到这一轮为止的全部问答**（Q1A1，追问一次就是 Q1A1Q2A2，各写一行、不重写上一行）；**重开就是新对话** |
| 选中文字按 ⌥C | ⌥C（带选区） | 选区以引用块进输入栏（每行一个 `>`，空行只写 `>`），下面空一行、光标等在那里，补一句就问；与 ⌥A/⌥N 同一条读数路径，没有权限或没有选区时窗口照常打开、输入栏空着 |
| 菜单栏 | 「存为笔记」 | 与其它动作并列，显示当前快捷键 |
| 设置 | 快捷键 → 「存为笔记」行 + 「笔记」组（笔记文件路径、存结果开关） | |
| 命令行 | `config set note-shortcut=…` / `note-file=…` / `note-results=…` | 与上游其它字段同一套 schema |

代码布局（对我们的后续迭代友好：**新文件永不与上游冲突**）：

- 新增：`Sources/Cida/NoteStore.swift`（JSONL 追加 + 去重 + 时间格式）、`Sources/Cida/SelectionNote.swift`（动作本体）、
  `Tests/CidaTests/{NoteStoreTests,SelectionNoteTests}.swift`、`Design/spec/notes.md`（设计说明）、`scripts/package-fork-dmg.sh`（不公证的 DMG）。
- 改动（冲突面，约 200 行）：`AppLifecycle.swift`（热键/菜单/提示胶囊/面板文案接线 + 结果入库）、`AppModel.swift`（`saveNote` 注入 + 完成钩子 + `saveNoteFromPanel`）、
  `GlobalShortcut.swift`（`.saveNote` + `optionN`）、`Models.swift`（`noteShortcut`/`noteFile`/`noteResults` + Codable）、
  `ConfigurationFields.swift`（三个 CLI 字段）、`PanelWindow.swift`（`NoteShortcutRouting` + ⌘S 分支）、`SettingsView.swift`（两行 + 一组 + 开关）、
  `SelectionImprovement.swift`（`onGenerated` 回调）；设计面 `Design/spec/{notes,settings}.md` 与 `Design/boards/components.js`（设置板补上笔记组）。
- 快速问答（2026-10-04）同样是新文件：`Sources/Cida/ChatModel.swift`（一轮对话的状态、流式回答、增量合成笔记文本）、
  `Sources/Cida/ChatView.swift`（窗口内容：提问在 surface、回答在 paper、底部输入栏）、`Sources/Cida/ChatWindow.swift`（浮窗与窗口级按键）、
  `Tests/CidaTests/ChatModelTests.swift`、`Design/spec/chat.md`、`Design/boards/chat.html`。
  改动面：`GlobalShortcut.swift`（`.askChat` + `optionC`）、`Models.swift`（`chatShortcut`/`chatSystemPrompt`/`chatPrompt` + Codable 与迁移）、
  `ConfigurationFields.swift`（`chat-shortcut`/`chat-prompt`）、`SettingsView.swift`（快捷键一行 + 动作页「问答」组）、`AppLifecycle.swift`（热键/菜单/截图状态/笔记回调）、
  `ModelPrompt.swift`（`ModelPromptMessage` + `messages`）、`ModelService.swift`（多轮 `messages` 进请求体 + 按 prompt 发送）、
  `SelectionNote.swift`（`saveChat`）；设计面 `Design/spec/settings.md`、`Design/spec/notes.md` §六、`Design/boards/components.{css,js}`。

## 三、数据：一份自己的收件箱

默认写 `~/.cida/items.jsonl`（可用 `note-file` 或设置改）。
一行一条 JSON，键按字母序，中文与斜杠不转义；字段固定：`schema`(1) / `id` / `ts`(ISO 8601 带毫秒与时区) / `source` / `text` / `note` / `app{name,bundle_id}` / `copied`。
`source` 是 `selection`、`clipboard`、`translation`、`improvement` 或 `chat`；`note` 平时是 `null`，
自动入库的那两种把译文/改写结果放在这里，`text` 始终是原文（`chat` 是例外：`text` 是整段问答，见 §二）。
写入用 `O_APPEND` + 单次 `write`，所以辞达与任何别的写入者（脚本、其它工具）可以同时追加而不会互相覆盖。
60 秒内、同一个 App、`text` 与 `note` 都相同才算重复，只提示不重复写入（所以同一段原文重新生成出不同结果会各留一行）。

```bash
jq -c 'select(.source == "translation")' ~/.cida/items.jsonl        # 只看翻译
jq -r 'select(.note) | "\(.text)\t\(.note)"' ~/.cida/items.jsonl    # 原文与译文/改写对照
jq -r '.app.name // "-"'  ~/.cida/items.jsonl | sort | uniq -c | sort -rn
```

## 四、怎么构建、怎么装（本机 macOS 27 / Swift 6.3）

```bash
# 编译 + 全部单测
swift build -Xswiftc -warnings-as-errors
swift test

# 出 App（dev 变体：独立 bundle id com.xuanwo.Cida.dev、独立设置与权限、不自动更新，所以上游发版不会覆盖我们的 fork）
CIDA_VARIANT=dev \
CIDA_CODESIGN_IDENTITY="Apple Development: dvorak4tzx@gmail.com (XW4WQ3LXFF)" \
  scripts/build-app.sh          # → build/Cida Dev.app

rm -rf "/Applications/Cida Dev.app"
cp -R "build/Cida Dev.app" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Cida Dev.app"
open "/Applications/Cida Dev.app"

# 换机器：打包成 DMG（不公证，Apple Development 签名就够自己用；上游 scripts/build-dmg.sh 要 Developer ID + 公证票据，只有发版才有）
CIDA_VARIANT=dev \
CIDA_CODESIGN_IDENTITY="Apple Development: dvorak4tzx@gmail.com (XW4WQ3LXFF)" \
  scripts/build-app.sh
scripts/package-fork-dmg.sh "build/Cida Dev.app" build/Cida-Dev.dmg
```

两点本机经验（换机器时照抄）：

1. **构建卡在 Sparkle**：`build-app.sh` 要下载 Sparkle 的二进制包（GitHub release）。走本机 LAN 代理约 18KB/s，ghfast.top 直连会超时。
   做法：断点续传把包拉完整（`curl -C - --max-time 200` 反复几次，约 10MB），用 Sparkle `Package.swift` 里的 `checksum` 校验 sha256，
   再按 SPM 缓存命名规则（URL 里非字母数字全换成 `_`）放到
   `~/Library/Caches/org.swift.swiftpm/artifacts/https___github_com_sparkle_project_Sparkle_releases_download_2_10_0_Sparkle_for_Swift_Package_Manager_zip`，
   之后 `swift build` 不再联网。
2. **签名**：`build-app.sh` 默认只认 "Developer ID Application" 证书（本机没有），所以要显式给 `CIDA_CODESIGN_IDENTITY`（用 Apple Development 即可）。
   只有需要公证/发布才需要 Developer ID。

装完有两件**一次性**的系统设置（macOS 26 起的行为，App 无法代做）：

- **辅助功能权限**给「辞达 Dev」：读选区靠它，读不到时要发的 ⌘C 兜底也靠它。按一次 ⌥N/⌥A 会自动打开 系统设置 → 隐私与安全性。
- **菜单栏图标**默认被 macOS 放进"隐藏区"：点菜单栏右侧的 `»` 展开，按住 ⌘ 把「辞达」拖进菜单栏一次即可（位置会记住）。

DMG 是 Apple Development 签名、没有公证，换机器第一次打开要**右键 →「打开」**（或在终端 `xattr -dr com.apple.quarantine "/Applications/Cida Dev.app"`），
之后系统就记住这个 App 了；辅助功能与屏幕录制权限在新机器上要重新授予。

## 五、跟进上游

```bash
cd ~/git/cida
# 两个 remote：origin = 我们自己的私有镜像 git@github.com:district10/cida.git（推送目标，SSH）；
# upstream = 上游真身 https://github.com/Xuanwo/cida.git（只读）
# 国内取上游：直接打 github.com 很慢（实测 ~70KB/s），走镜像（实测 ~2.5MB/s）
git fetch https://ghfast.top/https://github.com/Xuanwo/cida.git main:refs/remotes/upstream/main
git rebase upstream/main
swift build -Xswiftc -warnings-as-errors && swift test
```

本仓库原先是 `--depth 1 --single-branch` 的浅克隆（历史只到 `33c1518`，10 个 commit），推送到 GitHub 会因历史不完整而受限。
2026-10-03 已按上面的镜像地址 `git fetch --unshallow` 补全：根提交 `b7162bb`、215 个 commit、tag `v1.0.0`–`v1.5.1`，
`.git` 现在约 400MB（全量历史里的截图与 gif）。推送用 `git push -u origin main notes`，之后 `git fetch origin` 按通配 refspec 跟踪两个分支。

冲突预期：我们的**新文件**（NoteStore / SelectionNote / 两个测试 / spec）不会冲突；
**改动面**集中在 §二 列的那 7 个文件，且都是"各加一小段"的形式——上游若改动同一区域会有小冲突，按各自意图合并即可。
上游的 `AGENTS.md`、`Design/` 规则照旧遵守（设计先行、界面改动要带截图、`-warnings-as-errors` 与 `swift test` 必须过）。

## 六、能力现状

| 能力 | 现状 | 说明 |
| --- | --- | --- |
| 划词存笔记 | ✅ ⌥N | 比右键服务省事，不必先去设置里勾选 |
| 剪贴板一键存 | ✅ ⌥N 回退 | 没选中文字时存剪贴板，不必先切到菜单栏 |
| 翻译/改写的结果也留下 | ✅ 默认开 | 每次生成成功自动追一行（原文 `text` + 结果 `note`）；设置里的「存结果」或 `note-results=false` 可关 |
| 快速问答 | ✅ ⌥C | 浮窗问一句、接着追问，模型与端点用现有配置，system 提示词在设置（动作页「问答」组）或 `chat-prompt` 里改；每答完一轮把整段问答（Q1A1 → Q1A1Q2A2…）各追一行，`source=chat`；重开即新对话，不做历史 |
| 存之前补一句备注（人写的，进 `note` 字段） | ❌ 未做 | `note` 现在装自动入库的结果；人写的备注框还没做，要结构化备注得在面板加输入框（配 `Design/spec/panel.md` 更新） |
| `copied{ts,app}`（这份剪贴板何时从哪复制） | ❌ 未做 | 需要常驻轮询 `NSPasteboard.changeCount`（约 40 行）；辞达不做，`copied` 恒为 `null` |
| 从命令行/stdin 灌入一条笔记 | ❌ 未做 | 要的话给辞达 CLI 加一个 `note add` 子命令，走同一个 `NoteStore` |
| 提示反馈、去重、可配路径、菜单栏、CLI 配置 | ✅ | |

## 七、已验证 / 未验证（2026-10-03，本机 macOS 27.0 arm64）

- ✅ `swift build -Xswiftc -warnings-as-errors` 干净；笔记相关单测（存储格式、去重含结果、动作行为、⌘S 路由、面板接线、剪贴板回退、结果入库、⌥F 回调、设置与 CLI 字段）全绿。
- ✅ 全量 `swift test`：**只剩 2 个失败，且在未改动的 HEAD 上同样失败** —— 本机键盘是 dvorak(mod) 时，
  `GlobalShortcut.displayText` 显示的是按键实际字符（如 ⌥⇧E），而测试断言 US 位置名（⌥⇧D）。这是上游的既有问题，
  与笔记功能无关，值得给上游提 issue。
- ✅ 设置界面：`Design/boards/components.js` 补齐了「存为笔记」行与「笔记」组（含「存结果」），
  `Design/QACurrent/comparison-settings-shortcuts.png` 是原生截图与板的对照；`InteractionReproductionTests` 里
  快捷键页高度那条旧断言（板 525pt）本来就是坏的，这次按新板高 727pt 修好，该用例整条通过。
- ✅ 设置标签白屏（2026-10-03 修，两处提交：`3f63d5b` 与 `fix: move the Settings height change out of the layout pass`）：另一台 Mac（14" M1 Pro）上切到
  「翻译 / 快捷键 / 通用」会白屏或只画出下半截，要退出重开。**根因是那台机器开着「减弱动态效果」**（本机没开）：
  `CidaMotion.resolvedDuration` 返回 0，于是高度变化走"立即设窗口 frame"的分支，而它是在 SwiftUI 的布局回调**里**同步改窗口尺寸——
  窗口内容视图被留在中间高度（实测：窗口 363pt、内容视图 475pt），整个标签连标签栏一起被顶到窗口顶边之外，所以**再怎么点都切不动，只能重开**。
  现在：立即分支改为下一次主循环落地（不在布局回调里改窗口）、每次布局把内容视图对齐窗口内容区（改坏会写日志 `settings container repaired …`，category `settings`）、
  host 视图仍由 `placeHost` 手工钉住、每个标签一份滚动视图。
  另一台机器上的复现与验证用的是 app 自带的诊断：`"/Applications/Cida Dev.app/Contents/MacOS/Cida" --settings-tabs-cycle /tmp/cida-cycle`
  ——它会真的开出设置窗口、用真实点击逐一切标签（含快速连点），逐步写 `geometry.txt` 与每步截图，然后退出；
  离线自动化（`--design-state settings-*`）**不显示窗口**，所以永远走不到这条路径（这也是为什么 QA 截图一直正常）。
  注意：**覆盖安装会让那台机器上的辅助功能 / 屏幕录制授权失效**（TCC 按签名与 cdhash 记账），装完要重新授予，否则 ⌥A/⌥N 与截图翻译都不工作；
  设置窗口本身不受影响。
- ✅ 端到端：⌥A 开面板 → 填入文字 → ⌥N 落盘，记录 `source=selection`、`app=TextEdit`、时间戳正确，胶囊显示「已存入笔记 · TextEdit」。
- ⚠️ 自动入库的端到端（真实模型）没跑：单测覆盖了"完成的生成才入库、结果与原文成对、失败不写"，但一条真实的翻译落盘要你本机用一次确认；
  查 `log stream --predicate 'category == "shortcut"' | grep note-saved-result` 或直接 `tail -f ~/.cida/items.jsonl`。
- ⚠️ 面板里的 **⌘S**：代码路径与已验证的"⌥N 在面板打开时"完全相同，且有单测覆盖路由判定（`NoteShortcutRouting`）；
  但这台机器上**合成键盘事件进不了任何 App**（鼠标事件与 Carbon 全局热键可以），所以按键本身只能人工确认。
- ⚠️ 划词读取本身要有辅助功能权限才能端到端跑通（TCC 无法程序化授予）。
- ⚠️ 换机器安装：DMG 未公证，第一次打开要右键 →「打开」；权限要重新授予（见 §四）。

快速问答（2026-10-04，同一台机器）：

- ✅ 带入选区（同日晚些时候加）：`insertQuote` 的格式（多行、空行、CRLF、单行）与「引用 + 说明一起进这一轮的问题、也一起进笔记」有单测；
  `InteractionReproductionTests/testStagedQuoteLeavesTheCaretAfterIt` 用真编辑器确认光标落在引用块下面那一行（这条起名叫 Staged… 是为了落在 guest 分片 `test(Real|Replacing|Result|Settings|Staged)` 里，
  免得到 Tart 里被分片规则漏掉），板上的 `chat-quoted` 状态与原生截图逐行对得上。
- ✅ `swift build -Xswiftc -warnings-as-errors` 干净；`ChatModelTests`（14 条）覆盖「每答完一轮把整段问答各追一行」
  （`Q1A1` 与 `Q1A1Q2A2` 两条，停止/失败不写、重开清空且取消在跑的请求、追问把前几轮一起发给模型）与三种格式的请求体（`messages`/`input`/`system`）全绿；
  CLI 的 `chat-shortcut`/`chat-prompt`（含与其它快捷键不能相同）与「老配置拿到默认值、不抢别人的 ⌥C」也有单测。
  全量 `swift test` 359 条只剩上面那 3 条既有的 dvorak 断言失败（2 个用例），与本次无关。
- ✅ 界面：5 个状态（新对话 / 回答中 / 追问 / 失败 / 未配置）加深色都截了图，`Design/QACurrent/comparison-chat-*.png` 是板与原生截图的对照，
  `Design/ImplementationCurrent/chat-*.png` 是原生那张；设置页 `comparison-settings-{shortcuts,translation}.png` 重截（快捷键多一行「快速问答」，动作页多「问答」组）。
  截图全部走离线自动化（`scripts/run-isolated-automation.sh … --design-state chat-*`），没有动过本机屏幕。
  `InteractionReproductionTests` 里快捷键页的高度断言按新板改成 784pt（板 784、原生 782）。
- ⚠️ 真实模型的端到端没跑（本机没有 Key，只跑了桩服务）：一条真实问答落盘要自己试一次 —— 查
  `tail -f ~/.cida/items.jsonl`（应出现 `"source":"chat"` 的行）或 `log stream --predicate 'category == "shortcut"' | grep note-saved-chat`。
- ⚠️ ⌥C、⏎ 发送、⌘. 停止、Esc 关闭同样只能人工确认：本机合成键盘事件进不了任何 App（鼠标事件与 Carbon 全局热键可以）。
- ⚠️ Tart 的 XCUI 旅程这次没跑（本机没装 tart，`tart list` 不可用）：改动碰到设置与快捷键两页，按 AGENTS.md 该跑
  `CIDA_TART_DIAGNOSTIC_MODE=1 CIDA_UI_TEST_ONLY_TESTING=PanelAndSettingsJourneyTests/… scripts/test-ui-in-tart.sh` 那一片分片；
  在有 Tart 的机器或 release gate 上补一次。
- ⚠️ 窗口不因失焦而关闭（`Design/spec/chat.md` §一），所以「重开清空」只在真的重新打开时发生；如果更想要「点别处就收起」，改 `ChatController` 里一处即可。

## 八、后续可以做的

1. 人写的结构化备注（面板备注框 + `note` 字段的另一种用法），见 §六。
2. `copied` 来源信息（轮询 changeCount 的小追踪器）。
3. `cida note add`（stdin/参数灌入，给脚本与其它工具用）。
4. 若上游接受了笔记功能，这份 fork 可以退化成"只用上游 + 一个配置文件"。
