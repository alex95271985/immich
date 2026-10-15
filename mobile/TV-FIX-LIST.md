# Immich Android TV 修复清单 v2

| 项目 | 内容 |
|---|---|
| 依据 | `TV-COMPATIBILITY-REPORT.md`（原 18 项问题）+ 你对各问题的取舍答复 |
| 代码版本 | immich `2a8f8324e43487f29fd475832107f279da1c39c3`（与上一份报告同一版本） |
| 目标场景 | 自用：**TV 盒子上只看照片**；不上应用市场、不做修改/维护类操作 |
| 报告日期 | 2026-10-15 |

> 本清单只列修复项与代码落点，不修改任何代码。所有行号对应当前代码版本。

---

## 0. 先回答你的新需求：全屏展示 + 左右切换

一句话结论：**"点开全屏"已经有了；"遥控左右切换"没有，但改动是整份清单里最小的一个。**

| 环节 | 现状 | 结论 |
|---|---|---|
| 点缩略图打开大图 | `segment.model.dart:236-261`：`_handleOnTap` → `ctx.pushRoute(AssetViewerRoute(...))` | 已有 |
| 打开后是否全屏 | `asset_viewer.page.dart:259-262`：查看器把系统 UI 设为 `SystemUiMode.immersiveSticky`（隐藏状态栏/导航栏），背景纯黑 | 已是真全屏；但顶栏/底栏浮层默认显示，见下 |
| 触摸：左右滑动切换 | `asset_viewer.page.dart:311-317`：`PageView.builder` + `FastClampingScrollPhysics` | 已有 |
| 触摸：点左右 1/4 屏切换 | `asset_page.widget.dart:266-291`：`_onTapUp` → `onTapNavigate(±1)` | 代码已实现，但开关 `viewer.tapToNavigate` **默认 false**（`viewer_config.dart:12`），要在设置里打开 |
| 遥控：左右键切换 | Android 上左右键绑定的是 `DirectionalFocusIntent`（移焦点），不是翻页 | **没有**。且查看器里只有顶栏几个 `IconButton` 可聚焦，按左右键焦点在这些图标间跳，照片不动 |
| 遥控：确认键 | 只有触摸 tap 才会 `toggleControls`（`asset_page.widget.dart:273`） | **没有** |
| 打开时的控件浮层 | `providers/asset_viewer/asset_viewer.provider.dart:16`：`@Default(true) bool showingControls` → 一进来顶栏+底栏就盖在照片上 | 想"干净全屏"需要在 TV 上默认隐藏浮层 |

**关键好消息**：切页函数**已经写好**了 —— `_onTapNavigate(int direction)`（`asset_viewer.page.dart:97-108`），内部就是：

```dart
final target = page + direction;
if (target >= 0 && target <= _totalAssets - 1) {
  _pageController.jumpToPage(target);
  unawaited(_onAssetChanged(target));   // 连带 preload 下一张
}
```

所以"遥控左右键切上一张/下一张"= **把左右键绑到这个函数**。落点与坑见 N4。

**一个必须注意的连带点**：`_totalAssets` 来自 `timelineService.totalAssets`（`asset_viewer.page.dart:92`），也就是"时间线里已经加载过的照片数"。如果用户翻到已加载的末尾还想继续往右，就需要时间线能继续 append —— **这和 N3 是同一件事**，两个问题的修复可以互相验证。

---

## 1. 你的取舍 → 处理结果

| 原 ID | 你的答复 | 处理 |
|---|---|---|
| T1 Manifest TV 声明 | 能桌面启动、U 盘安装可接受、不上市场 | 降级为可选（N11），并说明为何"降级不等于零风险" |
| T2 瀑布流 | （仍要修） | 保留 P0，拆成 N2 + N3 |
| T3 登录输入法 | （仍要修） | 保留 P0（N1），额外补充一条"一次性绕过"路径 |
| T4 查看器手势 | 提出新需求：全屏 + 左右切换 | 升级为 P0（N4） |
| T5 PIN 锁屏 | 不需要 | 删除 |
| T6 OAuth | 不需要 | 删除 |
| T7 月份 scrubber | 未提 | 保留 P1 可选（N8） |
| T8 批量操作抽屉 | 不需要 | 删除。复核确认：该抽屉只在多选模式显示（`timeline.widget.dart:328-330`），删掉不影响任何"查看"路径 |
| T9 长按/双击/捏合 | 不需要多选 | 删除；仅把"缩放"作为可选项写在 N4 里 |
| T10 相册/相机权限 | 不需要，只想连服务器看图 | 改写为 N7：不是"申请权限"，而是"TV 上跳过整条权限+同步链路"，防卡 |
| T11 overscan | 未提 | 保留 P1 可选（N9） |
| T12 屏幕方向 | 电视永远横屏 | 降级为可选 1 行（N12） |
| T13 键盘遮挡 | 未提 | 保留 P1（N10），随 N1 一起处理 |
| T14 生物识别/超时锁 | 不需要 | 删除 |
| T15 一批平台能力 | 都不需要 | 删除大部分，只留 1 条启动期兜底（N13） |
| T16 布局密度 | 未提 | 保留 P1（N5） |
| T17 占位图 | 未提 | 保留 P1（N6） |
| T18 焦点视觉反馈 | 未提 | 升级 P0，并入 N2 |

---

## 2. 新清单总览

### P0 · 必须做，否则"在 TV 上看照片"这条路走不通

| 编号 | 原 ID | 事项 | 改动量 |
|---|---|---|---|
| N1 | T3 | 登录页能用遥控完成一次登录 | 中 |
| N2 | T2-B / T18 | 时间线网格可聚焦 + 焦点可见 | 中 |
| N3 | T2-A / T2-C | 让 D-pad 推进滚动并触发 append | 小到中 |
| N4 | T4 + 新需求 | 全屏查看 + 遥控左右切换 | 小 |

### P1 · 应做，明显影响体验

| 编号 | 原 ID | 事项 |
|---|---|---|
| N5 | T16 | TV 布局与密度（列数 / 间距 / 焦点框尺寸） |
| N6 | T17 | 用"按行预取"替代"速度判定"，避免一片占位图 |
| N7 | T10 | TV 上跳过相册权限与本地同步链路 |
| N8 | T7 | 月份快速跳转（可选，但查看场景很实用） |
| N9 | T11 | overscan 安全边距（可选，观感正常可跳过） |
| N10 | T13 | 软键盘遮挡（随 N1） |

### P2 · 可选 / 保险

| 编号 | 原 ID | 事项 | 备注 |
|---|---|---|---|
| N11 | T1 | Manifest 补 TV 声明 | 5 行 + 1 张 banner；换盒子/换启动器发现图标不见了再加 |
| N12 | T12 | 锁定横屏 | 1 行 |
| N13 | T15 残余 | 启动期平台调用兜底 try/catch | 只保留 `_setNavigationBarColor()` 这条没有 try/catch 的 |

---

## 3. 逐项详述

### N1 【P0】登录页：用遥控完成一次登录（原 T3）

**现象**：登录页弹出电视盒子输入法后，方向键与确认键无响应，无法输入、无法提交。

**根因**（已在引擎源码级确认）：Flutter 引擎对**每一个**输入框都无条件设置 `outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN`（`engine/.../editing/TextInputPlugin.java:346`），Dart 侧无法取消。而 Android TV 的 Leanback 输入法本质是"全屏输入法"，靠全屏接管画面、由系统把遥控按键投递给它。这个标志让它无法接管，按键落回 App；App 侧又把方向键消费在焦点遍历上，于是"键盘弹出来了，但完全不能操作"。

**三条可选路径**

**方案 A（最省事，建议先试）：插一次 USB 鼠标 / 飞鼠完成登录**

- 登录只需要成功一次，token 存在本地，之后不会再要求输入（除非换服务器、清数据、或你去开 Locked Folder 的 PIN）。
- 接一个 USB 鼠标或 2.4G 飞鼠，点击 Leanback 输入法的屏幕键盘即可完成输入与提交。
- 代价：0 代码改动。如果你能接受"装机时插一次鼠标"，**N1 可以整体降为 P2**。
- 局限：绕开的是"登录这一次"，不是"问题 1 本身"。输入法弹出后遥控彻底不响应的现象依旧存在。

**方案 B（彻底，建议作为最终形态）：TV 上不用 Flutter 的 TextField**

- 接一个 `PlatformView`，里面放原生 `EditText`（可用现成插件 `flutter_android_tv_text_field` / `tv_textfield`，或自研）。
- 原生 `EditText` 的 `EditorInfo` 由你自己控制，**不设** `IME_FLAG_NO_FULLSCREEN`，Leanback 输入法即可正常接管 D-pad。
- 落点：`packages/ui/lib/src/components/text_input.dart:69-87`（`ImmichTextInput` 实际渲染 `TextFormField` 的地方），按平台分支。

**方案 C（最稳，工作量大）：独立全屏录入 Activity**

- 字段本身只做只读展示；用户按确认键时启动一个"只有一个原生 `EditText`"的 Activity，输入完回传。
- 好处：输入法属于那个 Activity，完全没有跨层冲突，还顺带解决 N10 键盘遮挡。

**无论选哪个都要配套**

1. TV 上不要依赖"回车提交" —— `login_form.dart` 里的 `textInputAction: TextInputAction.go` + `onFieldSubmitted` 走的是 IME 的 action，而 IME 收不到按键。要显式提供可聚焦的提交按钮（`ImmichForm` 的 `ImmichTextButton` 本身可聚焦），并在按键处理里把确认键映射为 `form.submit()`。
2. `text_input.dart:79` 的 `onTapOutside: (_) => _focusNode.unfocus()` 只对指针事件有效。TV 上没有"点空白收起键盘"这条路，需要补一个"返回键退出编辑态"的路径。
3. 已知坑：Android TV 的输入法会吃掉 **key up** 事件，进出编辑态的判定建议放在 `KeyEvent` 的 up 阶段。

---

### N2 【P0】时间线网格：可聚焦 + 焦点可见（原 T2 原因B + T18）

**现状**：`segment.model.dart:304-317` 的每个 tile 只有一层 `GestureDetector`；`ThumbnailTile` 内部是纯 `Stack` / `Container` / `Hero`。全应用 0 处 `InkWell` / `Focus` / `canRequestFocus`。因此焦点在网格内**无处可去**，只能跳到左侧 `NavigationRail`、FAB 等少数可聚焦控件上 —— 这就是"只挪一小段"的直接原因。

**改法（最小改动版）**

```dart
// segment.model.dart:304 起
return RepaintBoundary(
  child: FocusableActionDetector(
    onShowFocusHighlight: (v) => setState(() => _focused = v),
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),  // D-pad 中心键
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),   // 部分盒子发 enter
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) => _handleOnTap(context, ref, assetIndex, asset, heroOffset, remoteSize),
      ),
    },
    child: GestureDetector( ... ),   // 触摸路径原样保留
  ),
);
```

**要点**

- D-pad 中心键在 Flutter 默认快捷键表里已绑定 `ActivateIntent`，这里用 `FocusableActionDetector` 自带的 `actions` 就近覆盖，比依赖默认 `ActivateAction` 更直观可靠。
- **焦点视觉不是装饰**：`_focused == true` 时给 tile 加亮色描边 + `scale 1.06`（或辉光）。TV 上"看不见焦点在哪"等于不可用，所以原 T18 必须和本条一起做。
- 遍历顺序：网格用 Flutter 默认策略基本可用 —— 同一 `Scrollable` 内的候选节点会被优先选取（`focus_traversal.dart:829-843`），跨列时按"焦点带宽"匹配。若实测"跳行/跳列"严重，再考虑引入 TV 导航库（`dpad` 等）。

---

### N3 【P0】让 D-pad 真正推进滚动并触发 append（原 T2 原因A + 原因C）

**这里要修正上一份报告的一个推断（重要）**

上一份报告建议"在时间线外层显式接管方向键为 `_scrollController.animateTo(±行高)`"。复核 Flutter 框架源码后确认：**内置的方向焦点遍历本身就会自动滚动**：

```dart
// flutter/packages/flutter/lib/src/widgets/focus_traversal.dart:201-217
static void defaultTraversalRequestFocusCallback(FocusNode node, {...}) {
  node.requestFocus();
  Scrollable.ensureVisible(node.context!, alignment: alignment ?? 1, ...);
}
```

也就是说：**只要网格里有可聚焦节点（N2）**，按"下"时 Flutter 会先把焦点移到下一个 tile，再自动把它 `ensureVisible` 滚进视野。于是整条链路变成：

```
按"下" → 焦点移到下一行 tile → ensureVisible 触发滚动 → scrollCacheExtent 窗口前移
      → 新的行被 build → 行 build 时才调用 timelineService.loadAssets()   ← 这就是 append
```

`loadAssets` 的触发点：`segment.model.dart:122`（行构建时）→ `timeline.service.dart:147-171`。

**所以 N3 的首选实现是"焦点驱动"，而不是"手动接管方向键"。** 手动接管的缺点是要自己实现"焦点跟着滚动走"，反而更复杂。

**但焦点驱动有两个必须补的洞**

1. **前沿停滞（frontier stall）**：焦点移到"已构建的最下面一行"后，再按"下"就没有候选节点了 —— 懒加载列表中未构建的行根本不存在 FocusNode，焦点停住 → 滚动停住 → append 也停住。**这就是"滑一小段就不动了"的深层机制。**
   对策（建议 a+b 一起做）：
   - a) **固定窗口预取**：行 build 时顺带为"后面第 2~3 行"提前触发 `loadAssets`（改 `segment.model.dart` 的行加载逻辑），保证前沿永远有已构建的行。
   - b) 引入 TV 导航引擎（`dpad` 包等），它在焦点碰到边界时会主动请求列表扩展，专门解决这个问题。
2. **`_DeferredRowLoader` 的占位图**：见 N6。滚动一旦被判定为"高速"，行只画占位图、完全不发请求，观感会变成"一片灰格子"。

**调优点**：`ensureVisible` 的 `alignment` 默认 1.0（把聚焦元素贴到视口尾部），按键滚动时视觉上会一次跳比较多。TV 上建议试 `alignment: 0.5`（居中）看哪种更舒服。

**保留的兜底**：如果焦点驱动在你的盒子上仍不理想（例如某些固件把 `KEYCODE_DPAD_DOWN` 当"滚动"上报），再叠加"按键 → `_scrollController.animateTo(offset ± 行高)`"这条显式路径。它不是首选，但是可控的后手。

---

### N4 【P0】全屏查看 + 遥控左右切换（你的新需求，原 T4 升级）

**目标**：点开一张照片 → 干净全屏 → 按左右键切上一张/下一张 → 按住能连续翻。

**改法**（落点：`asset_viewer.page.dart:288` 起，把 `AnnotatedRegion` 外面包一层）

```dart
return CallbackShortcuts(
  bindings: {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _onTapNavigate(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _onTapNavigate(1),
    const SingleActivator(LogicalKeyboardKey.select): () => _viewer.toggleControls(),
  },
  child: Focus(autofocus: true, child: AnnotatedRegion( ... )),
);
```

**要点与坑**

1. **必须有聚焦节点**：`CallbackShortcuts` 只在"焦点位于它子树内"时才生效。查看器内目前只有顶栏几个 `IconButton`。建议用 `Focus(autofocus: true, onKeyEvent: ...)` 让查看器页面本身拿到焦点，这样左右键才稳定生效。
2. **隐藏浮层时必须同步禁用焦点**：顶栏/底栏用的是 `IgnorePointer(ignoring: opacity < 1.0)`（`viewer_top_app_bar.widget.dart:71-73`、`viewer_bottom_app_bar.widget.dart:15-17`）。`IgnorePointer` 只挡指针事件、**不挡焦点** —— 于是照片全屏、控件不可见时，按左右键焦点会跑到"看不见的按钮"上，用户完全不知道发生了什么（表现为"遥控没反应"）。要加 `ExcludeFocus`（或 `canRequestFocus: false`）跟随 opacity 一起切换。
3. **"干净全屏"**：TV 上打开查看器时把 `showingControls` 设为 false（默认是 true），只在按确认键时唤出顶/底栏。`AssetViewer.setAsset()`（`asset_viewer.page.dart:68-77`）里已有"视频默认隐藏控件"的先例，照抄即可。
4. **翻到末尾要能继续加载**：`_onTapNavigate` 越过 `_totalAssets - 1` 会直接 return，这依赖 N3 让时间线持续 append，两条要一起验收。
5. **连续翻页**：按住方向键会按系统按键重复速率触发，每次 `jumpToPage` 都伴随一次 `_onAssetChanged`（含一次 DB 查询 + preload，`asset_viewer.page.dart:170-189`）。如果按住时卡顿，把这里的加载节流/合并即可。
6. **可选：缩放**。你只提了"切换"，没提缩放。TV 上如果要，用按键调 `PhotoView` 的 scale；如果不做，把左右键完全让给翻页即可。
7. **退出**：返回键本身是好的（Android 的 `KEYCODE_BACK` 会被 Flutter 正常交给导航栈），无需额外处理。

---

### N5 【P1】TV 布局与密度（原 T16）

**现状**：`packages/ui/lib/extensions/build_context_extensions.dart:20` 是 `bool get isMobile => width < 550;`，TV 逻辑宽 1920 → 判为"非手机"；默认 `tilesPerRow = 4`（`domain/models/config/timeline_config.dart:10`），1080p 下每格约 480px，一屏只显示 2 行多一点，密度不适合远距离观看。

**改法**：加设备画像判断（`UiModeManager.getCurrentModeType() == UI_MODE_TYPE_TELEVISION` 或 `hasSystemFeature("android.software.leanback")`），TV 默认 5~6 列、行间距加大、焦点框按尺寸放大；把散落的 `Platform.isAndroid` / `width < 550` 收敛到一个 `DeviceProfile`。

---

### N6 【P1】用"按行预取"替代"速度判定"（原 T17）

**现状**：`timeline.widget.dart:268` 用 `recommendDeferredLoading` 判定"滚太快" → `segment.model.dart:215-227` 直接返回占位图、不发请求。这个判定基于触摸滑动的速度模型，按键驱动下很容易一直命中"高速"，观感就是"看到一片灰格子、半天不出内容"。

**改法**：TV 路径不依赖速度判定，改为固定窗口预取（与 N3 的 a 项合并实现）。

---

### N7 【P1】TV 上跳过相册权限与本地同步（原 T10 改写）

**现状**：`login_form.dart:269-271` 登录后会 `requestGalleryPermission()` 并 `unawaited(handleSyncFlow())`。

**影响**：TV 上没有本地相册、没有相机，这些权限申请与本地扫描是空转，可能让"登录 → 首页"看起来卡住，或弹出无法用遥控操作的权限对话框。

**改法**：设备画像判定为 TV → 整条链路提前 return，只保留"远程浏览"。这正是你要的效果。

---

### N8 【P1 可选】月份快速跳转（原 T7）

**现状**：`scrubber.widget.dart:361-373` 只支持 `onVerticalDrag*` 拖拽，这是时间线**唯一**的"按月份跳转"入口。

**改法**：`_snapToSegment`（`:291-301`）内部用 `jumpTo` 直接跳转，本身可在键控下复用 —— 给 scrubber 加可聚焦能力，方向键映射"上一个月 / 下一个月"即可。查看场景下很实用，建议做。

---

### N9 【P1 可选】overscan 安全边距（原 T11）

**现状**：`main.dart` 设 `SystemUiMode.edgeToEdge`，而 TV 上 `MediaQuery.padding` 通常为 0 → 布局贴到物理边缘；电视过扫描会裁掉约 5%，左侧 `NavigationRail` 的文字标签与右侧 scrubber 的月份提示可能被切掉看不见。

**改法**：如果你现在的观感正常，可以先跳过；要改就给 TV 统一加一段安全边距，并按设备画像关掉 `edgeToEdge`。

---

### N10 【P1】软键盘遮挡（原 T13，随 N1）

**现状**：`AndroidManifest.xml:49` 的 `adjustResize` 与 `tab_shell.page.dart:89` / `timeline.widget.dart:353` 的 `resizeToAvoidBottomInset: false` 冲突。

**改法**：若走 N1 的方案 B/C，天然解决；若保留 Flutter 输入框，则键盘可见时（`MediaQuery.viewInsets.bottom > 0`）允许收缩，并把当前聚焦字段 `Scrollable.ensureVisible` 滚进视野。

---

### N11 【P2 可选】Manifest 补 TV 声明（原 T1）

你现在能启动、U 盘安装可接受，所以**不紧急**。但提醒两点：

- 不同 TV 启动器行为不一样。Android 官方启动器只列带 `LEANBACK_LAUNCHER` 的应用；**你的盒子能启动，说明它的启动器比较宽松**。换盒子 / 换固件 / 换启动器后，可能就"图标不见了"。
- 补它的成本很低：`<uses-feature android:name="android.software.leanback" android:required="false"/>` + `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>` + 一个 `LEANBACK_LAUNCHER` intent-filter + 一张 320×180 的 `banner`。属于"顺手加上、省得以后踩坑"。

---

### N12 【P2 可选】锁定横屏（原 T12）

`MainActivity` 加 `android:screenOrientation="landscape"`。你说电视永远横屏，如果你现在看到的是**左侧** `NavigationRail`（`tab_shell.page.dart:31,61`），说明盒子报告的确实是 landscape，可以不做。1 行的保险，加上也不亏。

---

### N13 【P2 可选】启动期兜底（原 T15 残余）

`main.dart` 的 `_setNavigationBarColor()` → `DeviceInfoPlugin().androidInfo` 没有 try/catch，异常会冒到全局错误处理。给这一处加 try/catch 就够了。其余（定位 / 地图 / 桌面小部件 / 通知 / 前台服务 / 分享 / UDID / 本地媒体）按你的答复全部不处理。

---

## 4. 明确不做

| 原 ID | 事项 | 你的理由 / 复核结论 |
|---|---|---|
| T5 | PIN 锁屏输入 | 不需要 Locked Folder |
| T6 | OAuth 登录 | 不需要 |
| T8 | 批量操作抽屉 | 不需要修改功能；复核确认该抽屉只在多选模式显示 |
| T9 | 长按多选 / 区间选择 / 捏合改列数 / 裁剪 | 不需要修改功能 |
| T10 | 相机 / 本地媒体权限本身 | 不需要 → 但改为"TV 上跳过"（N7），防止卡住登录后流程 |
| T14 | 超时锁定 / 生物识别 | 不需要 |
| T15 | 定位 / 地图 / 桌面小部件 / 通知 / 前台服务 / 分享 / UDID | 不需要（只留 N13 一条启动兜底） |

---

## 5. 实施顺序

**第一步 · 最小可用集（做完这 4 条，TV 上就能看图）**

1. N4 查看器左右键 —— 改动最小，先把"看图"闭环补上
2. N2 网格可聚焦 + 焦点样式
3. N3 焦点驱动滚动 + 预取（解决 append）
4. N1 登录 —— 若接受"插一次 USB 鼠标登录"，这条可以推到最后

**第二步 · 好用（P1）**

5. N7 跳过权限/同步 → 6. N5 密度 → 7. N6 预取 → 8. N8 月份跳转 → 9. N10 键盘遮挡 → 10. N9 overscan

**第三步 · 可选与工程化（P2）**

11. N11 / N12 / N13 → 12. 收敛出统一的 `DeviceProfile` → 13. 加键控回归测试（`tester.sendKeyEvent(LogicalKeyboardKey.arrowDown)` 断言焦点移动与滚动量）

---

## 6. 验收清单

**登录**

- [ ] 方案 A：插上鼠标能完成登录；方案 B/C：拔掉鼠标，遥控也能完成登录
- [ ] 键盘弹出后能用方向键在字符盘上选字、确认键完成输入
- [ ] 不用"回车"，按可聚焦的提交按钮能提交成功

**首页瀑布流**

- [ ] 按"下"每次推进一整行，不会"挪一小段就死住"
- [ ] 持续按"下"能一直往下；可观察到 `TimelineService.loadAssets()` 反复被调用、子项数持续增长（append 正常）
- [ ] 焦点框清晰可见（放大/描边），不会停在看不见的地方
- [ ] 确认键能打开当前聚焦的照片

**查看器（你的新需求）**

- [ ] 确认键打开后是干净全屏（无顶/底栏遮挡，或按确认键可唤出）
- [ ] 左/右键切上一张/下一张，按住可连续翻
- [ ] 翻到已加载末尾时能继续往右（依赖 N3）
- [ ] 返回键退出查看器，回到原来的滚动位置

---

## 7. 本次复核新增的证据

| 结论 | 证据 |
|---|---|
| 切页函数已存在，可直接复用 | `mobile/lib/presentation/widgets/asset_viewer/asset_viewer.page.dart:97-108` `_onTapNavigate` |
| 查看器已是真全屏 | 同上 `:259-262` → `SystemUiMode.immersiveSticky` |
| 触摸 tap 翻页默认关闭 | `asset_page.widget.dart:271-272` + `viewer_config.dart:12` `@Default(false)` |
| Flutter 焦点遍历会自动滚动 | `flutter/.../widgets/focus_traversal.dart:201-217` `defaultTraversalRequestFocusCallback` → `Scrollable.ensureVisible(alignment: 1.0)` |
| 同一 Scrollable 内候选节点优先（焦点不易乱跳） | 同上 `:829-843` |
| `IgnorePointer` 不挡焦点（隐藏浮层里仍会被聚焦） | `viewer_top_app_bar.widget.dart:71-73`、`viewer_bottom_app_bar.widget.dart:15-17` |
| `showingControls` 默认 true | `providers/asset_viewer/asset_viewer.provider.dart:16` |
| 批量抽屉只在多选模式出现 | `timeline.widget.dart:328-330` |
| "append"由行构建驱动 | `segment.model.dart:122` → `domain/services/timeline.service.dart:147-171` |
| Flutter 对所有输入框强制 `IME_FLAG_NO_FULLSCREEN`（N1 根因） | `engine/.../editing/TextInputPlugin.java:346` |
