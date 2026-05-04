# Flutter 开发经验总结

本文档记录 Focus Timer 项目开发过程中遇到的问题、根因及解决方案，供后续学习和复盘。

---

## 一、拖拽相关

### 1. LongPressDraggable 与 GestureDetector 嵌套导致点击失效

**问题**：任务项使用 `LongPressDraggable` 包裹 `GestureDetector`，导致拖拽后无法单击显示任务详情。

**根因**：`LongPressDraggable` 内部在长按开始时会自动触发 `onTap` 回调，与外部 `GestureDetector` 的 `onTap` 事件路由冲突。Flutter 的 hit testing 机制使得长按后点击事件无法正确传递到目标。

**解决方案**：
- 将 `GestureDetector` 放在 `LongPressDraggable` 的 `child` 内部，而非嵌套在外层
- 点击事件通过 `content` 内部的 `GestureDetector.onTap` 处理，与 `LongPressDraggable` 解耦
- 添加 `_isDragging` 状态标志，拖拽过程中禁用点击

```dart
// 错误写法
LongPressDraggable(
  child: GestureDetector(onTap: ...), // 嵌套导致事件冲突
)

// 正确写法
LongPressDraggable(
  child: GestureDetector(onTap: _isDragging ? null : widget.onTap, ...), // 解耦
  onDragStarted: () => setState(() => _isDragging = true),
  onDragEnd: (details) => setState(() => _isDragging = false),
)
```

### 2. 拖拽释放后点击事件无法触发

**问题**：拖拽任务到清单后，再点击任务无反应。

**根因**：`_isDragging` 状态没有在 `onDraggableCanceled` 时重置，导致点击被禁用。

**解决方案**：所有拖拽结束场景（正常放置、取消、错误）都统一重置 `_isDragging = false`。

---

## 二、文本框失焦自动保存

### 1. TextField 失焦不自动保存

**问题**：任务详情页的标题输入框和新建清单输入框，失焦后不会自动保存。

**根因**：只监听了 `onSubmitted`（回车）和 `onEditingComplete`（键盘完成），没有监听焦点丢失事件。

**解决方案**：使用 `FocusNode` 监听焦点变化。

```dart
// 1. 创建 FocusNode
late FocusNode _titleFocusNode;

// 2. 在 initState 中注册监听
_titleFocusNode.addListener(_onTitleFocusChange);

// 3. 焦点变化时处理
void _onTitleFocusChange() {
  if (!_titleFocusNode.hasFocus) {
    _saveTitle(widget.taskId);
  }
}

// 4. 在 dispose 中销毁
_titleFocusNode.removeListener(_onTitleFocusChange);
_titleFocusNode.dispose();

// 5. TextField 绑定 focusNode
TextField(focusNode: _titleFocusNode, ...)
```

---

## 三、溢出问题

### 1. Row 中按钮溢出（RIGHT OVERFLOWED）

**问题**：计时器面板中"开始/暂停"和"重置"按钮超出容器宽度，导致溢出警告。

**根因**：固定 `padding` 和 `SizedBox` 间距在窄容器（280px）中累加后超出可用宽度。

**解决方案**：
- 减小按钮 `padding`（如 `horizontal: 32` → `20`）
- 减小图标和文字尺寸
- 添加 `minimumSize: Size.zero` 防止按钮有默认最小尺寸
- 添加 `mainAxisSize: MainAxisSize.min` 避免 Row 撑满容器
- 固定文字字号避免不同状态文本宽度变化

```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    minimumSize: Size.zero, // 关键：允许按钮收缩
  ),
)
```

### 2. 高度超过 24 像素警告

**问题**：侧边栏"新建清单"按钮高度超出 24px。

**根因**：使用中文字符 `Text('+')` 作为图标，中文字符渲染高度可能超过预期。

**解决方案**：使用 Material 图标替代（如 `Icons.add`），高度固定为 20px。

---

## 四、DropdownButton 渲染错误

### 1. Cannot hit test a render box with no size

**问题**：设置页面的 DropdownButton 无法点击，控制台报错 "Cannot hit test a render box with no size"。

**根因**：`DropdownButton` 的 `underline` 属性使用 `const SizedBox()` 作为占位，但 `SizedBox` 没有实际尺寸，导致渲染盒尺寸为零。

**解决方案**：使用有尺寸的空容器替代。

```dart
// 错误
DropdownButton(underline: const SizedBox(), ...)

// 正确
DropdownButton(underline: Container(), ...)
```

---

## 五、重复操作防护

### 1. 新建清单时出现两个同名清单

**问题**：快速点击或回车时，可能创建两个同名清单。

**根因**：异步操作执行期间，状态未及时更新，用户可能再次触发创建。

**解决方案**：
- 先关闭输入框并清空内容，防止重复触发
- 使用短延迟确保 UI 先更新
- 添加 `mounted` 检查，防止 widget 卸载后操作

```dart
void _createList() async {
  if (_newListController.text.trim().isEmpty) {
    setState(() { _showNewList = false; _newListController.clear(); });
    return;
  }

  final name = _newListController.text.trim();

  // 先关闭输入框
  setState(() { _showNewList = false; _newListController.clear(); });

  // 延迟确保 UI 更新
  await Future.delayed(const Duration(milliseconds: 50));

  if (!mounted) return;
  final list = await ref.read(taskProvider.notifier).createList(name);
  // ...
}
```

---

## 六、ConsumerWidget 改为 ConsumerStatefulWidget 的注意事项

**问题**：将 `ConsumerWidget` 改为 `ConsumerStatefulWidget` 后，编译报错 "The getter 'task' isn't defined"。

**根因**：State 类中访问 widget 属性需要使用 `widget.xxx`，不能直接用 `xxx`。

**解决方案**：所有 `task.xxx` 改为 `widget.task.xxx`。

---

## 七、重要设计原则

1. **拖拽交互**：长按触发拖拽，短按/单击触发选择
2. **自动保存**：使用 FocusNode 监听失焦事件，而非依赖用户主动提交
3. **溢出防护**：窄容器中使用较小的 padding、图标和文字；添加 `minimumSize: Size.zero`
4. **状态同步**：异步操作前后检查 `mounted`，防止状态过期操作
5. **事件解耦**：避免 `LongPressDraggable` 和 `GestureDetector` 嵌套冲突

---

## 八、常用调试命令

```bash
# 构建 Windows Debug 版本
flutter build windows --debug

# 分析代码
flutter analyze

# 清除缓存重新构建
flutter clean
rm -rf build/
```