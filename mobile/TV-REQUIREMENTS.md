# Immich Android TV 修改任务需求书

| 项目 | 内容 |
|---|---|
| 依据 | `mobile/TV-FIX-LIST.md`(v2)+ 两轮问答确认(2026-10-15) |
| 代码版本 | immich `2a8f832`(已按此版本逐项核对代码落点,全部属实) |
| 目标场景 | 自用:TV 盒子上**只看照片**;不上应用市场、不做修改/维护类操作 |
| 登录方式 | **插一次 USB 鼠标/飞鼠完成登录**(token 持久化,仅此一次) |

---

## 1. 决策记录(两轮问答结论)

| 决策点 | 结论 | 影响 |
|---|---|---|
| N1 登录方案 | **A:插一次鼠标,零代码** | N1、N10 整体取消,不在本轮改动范围 |
| N3 滚动方案 | **纯 Flutter 焦点驱动 + 自写预取** | 不引入第三方 TV 导航库;显式 animateTo 兜底不做,真机不理想再议 |
| N5 TV 列数 | **6 列**(1080p 每格约 320px) | `tilesPerRow` TV 默认 6,非 TV 保持 4 |
| P1 范围 | **N7 + N8 做;N9 overscan 不做** | 观感正常,不加安全边距 |
| P2 范围 | **N11 + N12 + N13 全做** | banner 用 `design/` 资源生成 320×180 |
| 回归测试 | **不加**,全部真机按验收清单逐项验 | 现有测试不得因改动而挂 |
| TV 判定 | 自动检测(UiModeManager + leanback feature 双重),**不做**设置页手动开关 | 若真机检测失败,后续再补覆盖开关 |

---

## 2. 对原清单的两处修正(已核实代码)

1. **文件路径**:原清单所有 `segment.model.dart` 引用,实际文件是
   `mobile/lib/presentation/widgets/timeline/fixed/segment.model.dart`(主时间线走 `timeline.state.dart:82` → `FixedSegmentBuilder`)。同级 `timeline/segment.model.dart` 是 97 行的抽象类,**不要改错文件**。
2. **N7 遗漏调用点**:权限 + 同步链路在 `login_form.dart` 有**两处**——`:269-273`(登录成功后)和 `:374-378`(权限被拒后的引导路径)。两处都要在 TV 上跳过。

---

## 3. 公共基础设施:DeviceProfile

新增统一的设备画像工具(建议落点 `mobile/lib/utils/device_profile.dart`,实现时定):

- TV 判定 = `device_info_plus` 的 `AndroidUiModeType.typeTelevision` **或** `hasSystemFeature("android.software.leanback")`,二者其一命中即 TV;
- 结果缓存,暴露同步 getter(如 `DeviceProfile.isTV`);
- N4 / N5 / N7(以及后续任何 TV 分支)一律经由它判断,**不得**散落 `Platform.isAndroid` / 宽度阈值判断;
- 首个使用方出现时即创建(N2 阶段前),后续各项复用。

---

## 4. 任务明细

### T1(=N2)【P0】时间线网格可聚焦 + 焦点可见

**落点**:`fixed/segment.model.dart:300-317` `_AssetTileWidget`(现为 `RepaintBoundary → GestureDetector → ThumbnailTile`)

**要点**:
- 外层包 `FocusableActionDetector`,`shortcuts` 绑 `LogicalKeyboardKey.select` 与 `enter` → `ActivateIntent`,`actions` 就地覆盖为 `_handleOnTap(...)`(触摸 `GestureDetector` 路径原样保留);
- 焦点高亮:亮色描边 + `scale 1.06`(需要 `_focused` 状态,`_AssetTileWidget` 需从 `ConsumerWidget` 转为 StatefulWidget 或等效方案);
- 遍历依赖 Flutter 默认策略(同 Scrollable 内候选优先);若真机实测跳行/跳列严重,备选方案为引入 TV 导航库(**本轮不做**)。

**验收**:方向键能在网格内逐格移动、焦点框清晰可见;确认键打开当前聚焦照片。

### T2(=N3+N6)【P0】焦点驱动滚动 + 固定窗口预取

**落点**:`fixed/segment.model.dart:115-130`(行构建触发 `loadAssets` 处)、`:210-227`(`_DeferredRowLoader`);配合 `timeline.widget.dart:268` 的 `recommendDeferredLoading` 判定。

**要点**:
- 滚动不自接管方向键:靠 T1 的可聚焦节点 + Flutter 默认 `ensureVisible`(焦点到哪滚到哪);
- **预取**:行 build 时为后续第 2~3 行提前触发 `timelineService.loadAssets()`,保证焦点前沿永远有已构建的行(解决前沿停滞);
- **绕过速度判定**:TV 路径下 `recommendDeferredLoading` 恒为 false(`_DeferredRowLoader` 不再因此只画占位图),避免按键驱动被误判"高速滚动"而一片灰格子;
- `ensureVisible` 的 `alignment` 默认 1.0,实现时可试 0.5(居中)取观感更好者;
- 显式 `animateTo` 按键接管**不做**,留作真机不理想时的后手。

**验收**:按"下"每次推进一整行;持续按"下"能一直往下,`loadAssets()` 持续被调用、子项数持续增长;不出现整屏占位图。

### T3(=N4)【P0】查看器全屏 + 遥控左右切换

**落点**:`asset_viewer.page.dart:288` 起(`AnnotatedRegion` 外层)、`asset_viewer.provider.dart`(showingControls)、`viewer_top_app_bar.widget.dart:71-73` 与 `viewer_bottom_app_bar.widget.dart:15-17`(IgnorePointer)。

**要点**:
- 外包 `CallbackShortcuts` + `Focus(autofocus: true)`:
  - `arrowLeft` → `_onTapNavigate(-1)`,`arrowRight` → `_onTapNavigate(1)`;
  - `select` **和** `enter` → `toggleControls()`(与 T1 保持一致,部分盒子发 enter);
- TV 打开查看器默认 `showingControls = false`(仿 `setAsset()` 的视频先例,`asset_viewer.page.dart:68-77`),按确认键唤出/隐藏顶底栏;
- 浮层隐藏时同步禁焦点:`IgnorePointer` 只挡指针不挡焦点,须随 opacity 联动加 `ExcludeFocus`(或 `canRequestFocus: false`),否则左右键焦点会跳到看不见的按钮上;
- 连续翻页:按住方向键按系统重复速率触发,`_onAssetChanged`(含 DB 查询 + preload)需节流/合并,防卡顿;
- 缩放**不做**,左右键完全让给翻页;返回键退出走系统默认,不改。

**验收**:打开即干净全屏;左右键切换并支持按住连翻;翻到已加载末尾能继续(依赖 T2);返回键退回原滚动位置。

### T4(=N5)【P1】TV 布局密度:默认 6 列

**落点**:`domain/models/config/timeline_config.dart:10`(`tilesPerRow = 4`)。

**要点**:TV(DeviceProfile)默认 `tilesPerRow = 6`,非 TV 保持 4;焦点描边/间距按 320px 级格子取值(实现时定具体常量)。

**验收**:1080p 下一屏约 3 行,格子与焦点框在沙发距离清晰可辨。

### T5(=N7)【P1】TV 跳过相册权限与本地同步

**落点**:`login_form.dart:269-273` 与 `:374-378` **两处**。

**要点**:`DeviceProfile.isTV` → 两处均提前 return:不 `requestGalleryPermission()`、不 `handleSyncFlow()`,只保留远程浏览链路,防权限弹窗/空转同步卡在"登录 → 首页"。

**验收**:TV 登录(鼠标)后直达时间线,无权限对话框、无同步转圈。

### T6(=N8)【P1】月份 scrubber 键控跳月

**落点**:`scrubber.widget.dart`(`:291-301` `_snapToSegment`、`:361-373` 现仅支持垂直拖拽)。

**要点**:scrubber 加可聚焦能力,方向键映射"上一个月 / 下一个月",复用 `_snapToSegment` 的 `jumpTo`;靠默认焦点遍历从网格可达即可,**不**额外加快捷键。

**验收**:焦点移到 scrubber 后,上下键按月跳转时间线。

### T7(=N11)【P2】Manifest 补 TV 声明 + banner

**落点**:`mobile/android/app/src/main/AndroidManifest.xml`、`mobile/android/app/src/main/res/drawable/banner.png`(新增)。

**要点**:
- `<uses-feature android:name="android.software.leanback" android:required="false"/>`
- `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`
- `MainActivity` 增加 `LEANBACK_LAUNCHER` intent-filter;
- `application` 加 `android:banner="@drawable/banner"`,banner 用 `design/` 下 logo 资源生成 **320×180** PNG。

**验收**:U 盘安装后,标准 Android TV 启动器"应用行"出现 Immich 图标与 banner。

### T8(=N12)【P2】锁定横屏

**落点**:Manifest 中 `MainActivity` 加 `android:screenOrientation="landscape"`。

**备注**:Manifest 静态属性无法按设备区分——此 fork 若还装到手机上,手机也会被锁横屏。当前用途为 TV 专用 fork,可接受;如日后需要手机复用,改为代码侧 `SystemChrome.setPreferredOrientations` 按 DeviceProfile 分支。

### T9(=N13)【P2】启动兜底 try/catch

**落点**:`main.dart:175` `_setNavigationBarColor()`(`DeviceInfoPlugin().androidInfo` 无异常保护)。

**要点**:包 try/catch,异常不再冒到全局错误处理。其余平台能力(定位/地图/小部件/通知/前台服务/分享/UDID/本地媒体)按原清单第 4 节全部不处理。

---

## 5. 明确不做(最终版)

| 项 | 说明 |
|---|---|
| N1 登录页遥控输入 | 改用"插一次鼠标"绕过;引擎层 `IME_FLAG_NO_FULLSCREEN` 根因不处理 |
| N9 overscan 边距 | 真机观感正常 |
| N10 软键盘遮挡 | 随 N1 取消 |
| 键控回归测试 | 真机验收;现有自动化测试不得挂 |
| T5/T6/T8/T9/T14/T15 等 | 沿用原清单第 4 节结论 |
| 第三方 TV 导航库 / 显式按键接管滚动 | 本轮不做,留作后手 |

---

## 6. 实施顺序与构建验证

**阶段一 · 看图闭环(P0)**:DeviceProfile → T1 网格聚焦 → T2 滚动+预取 → T3 查看器
**阶段二 · 体验(P1)**:T5 跳过权限/同步 → T4 六列 → T6 跳月
**阶段三 · 打包保险(P2)**:T7 Manifest+banner → T8 锁横屏 → T9 try/catch

每阶段完成后:
- `mise //mobile:lint`(dart analyze + dcm)、`mise //mobile:format`、`mise //mobile:test`(现有测试)必须通过;
- 涉及生成文件时先 `mise //mobile:codegen`;
- 用已改为 `ubuntu-latest` 的 GitHub Actions workflow 出 APK,真机按第 7 节验收。

---

## 7. 总验收清单(真机)

**登录(鼠标)**

- [ ] 插 USB 鼠标可完成服务器地址/邮箱/密码输入并登录成功
- [ ] 登录一次后拔掉鼠标,重启 App 不再要求输入

**首页瀑布流**

- [ ] 按"下"每次推进一整行,不会"挪一小段就死住"
- [ ] 持续按"下"能一直往下;`loadAssets()` 反复调用、子项数持续增长
- [ ] 焦点框清晰可见(描边+放大),不停在看不见的地方
- [ ] 确认键打开当前聚焦的照片
- [ ] 默认 6 列,沙发距离格子清晰
- [ ] 无权限弹窗、无本地同步卡顿
- [ ] (T6)scrubber 可聚焦,上下键按月跳转

**查看器**

- [ ] 打开后干净全屏(无顶/底栏,或按确认键可唤出)
- [ ] 左/右键切上一张/下一张,按住可连续翻且不卡顿
- [ ] 翻到已加载末尾能继续往右
- [ ] 返回键退出查看器,回到原滚动位置

**安装与启动**

- [ ] U 盘安装成功;标准 TV 启动器应用行显示图标 + banner
- [ ] 启动无崩溃(T9 兜底生效)

---

## 8. 风险与备注

1. **N12 锁横屏是全局的**:此 fork 装到手机也会被锁横屏(见 T8 备注)。
2. **CI 签名**:当前 fork 无官方 keystore,`ubuntu-latest` 每次构建 debug 签名都不同,**版本之间无法覆盖升级**,每次需先卸载。长期使用建议自配 4 个 secrets(`KEY_JKS`/`ALIAS`/`ANDROID_KEY_PASSWORD`/`ANDROID_STORE_PASSWORD`)。
3. **上游合并冲突**:改动集中在 `fixed/segment.model.dart`、`asset_viewer.*`、Manifest 等上游活跃文件,后续 sync upstream 可能有冲突,属预期维护成本。
4. **焦点遍历差异**:个别盒子固件对 D-pad 上报行为不同,若真机出现"跳行/跳列"或停滞,后手方案(显式按键接管 / `dpad` 库)已在决策记录中预留。
