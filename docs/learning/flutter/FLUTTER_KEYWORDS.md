# Flutter / Dart 手写速查（RN 开发者版）

> 通用参考，不绑定具体项目。Flutter = UI 框架，Dart = 语言。

---

## 1. 心智模型

| Flutter / Dart | RN 类比 |
|----------------|---------|
| Dart | JavaScript / TypeScript |
| Flutter | React Native + React |
| Widget | Component（无 DOM、无 JSX） |
| `Widget(...)` | `<Widget />` |
| `build()` | `render()` / 函数 return |
| `setState()` | `useState` setter / class setState |
| `pubspec.yaml` | `package.json` |
| `flutter pub get` | `npm install` |

**没有 DOM。** UI = Widget 树 → Element 树 → RenderObject（布局/绘制）。

---

## 2. 最小可运行 App

```dart
// main.dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(child: Text('Hello')),
    );
  }
}
```

---

## 3. 两种 Widget

### StatelessWidget — 无内部可变 state

```dart
class Greeting extends StatelessWidget {
  const Greeting({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Text('Hi $name');
}

// 使用
Greeting(name: 'Tom')
```

### StatefulWidget — 有内部 state

```dart
class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  void _increment() {
    setState(() => _count++);   // 必须 setState 才刷新 UI
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _increment,
      child: Text('$_count'),
    );
  }
}
```

| | StatelessWidget | StatefulWidget |
|---|-----------------|----------------|
| 何时用 | 纯展示，全靠 props | 输入、动画、loading、表单 |
| 数据 | `final` 字段 | `State` 里的变量 |
| 读 props | 直接用字段名 | 用 `widget.xxx` |

---

## 4. 组件定义固定套路

```dart
class MyCard extends StatelessWidget {
  const MyCard({
    super.key,              // 可选，传给 Widget 基类（≈ React key）
    required this.title,    // 必传命名参数
    this.onTap,             // 可选命名参数
  });

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(title), onTap: onTap);
  }
}
```

| 关键字 | 含义 |
|--------|------|
| `super.key` | 组件 identity，列表/测试常用 |
| `required this.xxx` | 必传 prop，自动赋给同名字段 |
| `final` | 只读；引用不可换，对象内容可能可改 |
| `const 构造函数` | 编译期常量 Widget，性能更好 |
| `_` 前缀 | 文件内私有 |
| `@override` | 重写父类方法，拼错名会报错 |

---

## 5. Dart 语法（写 Flutter 必会）

```dart
// 变量
final name = 'Tom';        // 运行期常量，不可重新赋值
const pi = 3.14;           // 编译期常量
late final repo;           // 延迟初始化一次
String? maybe;             // 可 null
maybe ?? 'default';        // 空则默认值
maybe?.length;             // 安全访问

// 函数
void noop() {}
int add(int a, int b) => a + b;           // 单行箭头
Future<void> load() async { await ...; }  // 异步

// 命名参数（Widget 构造函数几乎全是这种）
Foo({required this.a, this.b = 0});

// 级联
final paint = Paint()
  ..color = Colors.red
  ..strokeWidth = 2;

// 不可变更新
user.copyWith(name: 'New');

// import：引入文件，文件内 public 类名直接可用（无 import X from）
import 'package:flutter/material.dart';
import '../models/user.dart';
```

---

## 6. 布局 Widget

| Widget | RN 类比 | 手写要点 |
|--------|---------|----------|
| `Column` | column flex | `mainAxisAlignment` / `crossAxisAlignment` |
| `Row` | row flex | 同上 |
| `Expanded` | `flex: 1` | **必须在** Column/Row 内 |
| `Flexible` | flex 可 shrink | 类似 Expanded 但更灵活 |
| `Stack` | 绝对叠层 | 配合 `Positioned` |
| `Positioned` | absolute | `top/left/right/bottom` |
| `Center` | 居中 | 单 `child` |
| `Padding` | padding | `EdgeInsets.all(16)` |
| `SizedBox` | 固定宽高 | `SizedBox(height: 8)` |
| `Container` | View + style | 宽高、颜色、边距、装饰 |
| `SafeArea` | SafeAreaView | 避开刘海/底栏 |
| `Spacer` | flex spacer | Column/Row 内撑开 |

```dart
Scaffold(
  body: Column(
    children: [
      const Text('Header'),
      Expanded(child: ListView(...)),  // 中间撑满
      ElevatedButton(onPressed: () {}, child: const Text('OK')),
    ],
  ),
)
```

**规则：** 多数槽位（如 `Scaffold.body`）只接受 **1 个** Widget；多个元素用 Column/Stack 包一层。

---

## 7. 常用 Material Widget

| Widget | 用途 |
|--------|------|
| `MaterialApp` | App 根：主题、路由、locale |
| `Scaffold` | 页面壳：appBar / body / fab / drawer |
| `AppBar` | 顶栏 |
| `Text` | 文本 |
| `ElevatedButton` / `TextButton` / `IconButton` | 按钮 |
| `TextField` | 单行输入 |
| `Image.network` / `Image.asset` | 图片 |
| `Icon(Icons.home)` | Material 图标 |
| `Divider` | 分割线 |
| `Card` / `ListTile` | 列表项 |
| `SnackBar` | 底部提示 |
| `AlertDialog` | 弹窗 |
| `CircularProgressIndicator` | Loading |
| `Switch` / `Checkbox` / `Radio` | 表单控件 |

---

## 8. 列表

```dart
// 固定少量项
ListView(
  children: [
    ListTile(title: Text('A')),
    ListTile(title: Text('B')),
  ],
)

// 大量数据（≈ FlatList）
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    final item = items[index];
    return ListTile(
      key: ValueKey(item.id),   // 列表项建议加 key
      title: Text(item.name),
      onTap: () => onTap(item),
    );
  },
)

// 网格
GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
  ),
  itemCount: items.length,
  itemBuilder: (context, index) => ...,
)
```

---

## 9. 条件渲染

```dart
// 三元
isLoading
    ? const CircularProgressIndicator()
    : const Content();

// Collection if（children 列表里）
children: [
  if (showBanner) const Banner(),
  if (items.isNotEmpty) ItemList(items: items),
]

// switch 表达式（Dart 3+）
final label = switch (mode) {
  Mode.a => 'A',
  Mode.b => 'B',
};
```

≈ RN 的 `{cond && <X />}`

---

## 10. 手势 & 输入

```dart
// 高层手势（tap / longPress / drag）
GestureDetector(
  onTap: () => print('tap'),
  child: Container(color: Colors.blue, height: 48),
)

// 原始 pointer（手写、笔压、多指）
Listener(
  onPointerDown: (e) => ...,
  onPointerMove: (e) => ...,
  onPointerUp: (e) => ...,
  child: ...,
)

// 输入框 + Controller
final controller = TextEditingController();

TextField(
  controller: controller,
  decoration: const InputDecoration(
    hintText: 'Search',
    border: OutlineInputBorder(),
  ),
  onChanged: (value) => ...,
)

@override
void dispose() {
  controller.dispose();   // 必须释放
  super.dispose();
}
```

---

## 11. 异步 UI

```dart
// Future → UI
FutureBuilder<User>(
  future: fetchUser(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const CircularProgressIndicator();
    }
    if (snapshot.hasError) return Text('Error');
    if (!snapshot.hasData) return const Text('No data');
    return Text(snapshot.data!.name);
  },
)

// Stream → UI（WebSocket、Firestore 等）
StreamBuilder<int>(
  stream: counterStream,
  builder: (context, snapshot) => Text('${snapshot.data ?? 0}'),
)
```

---

## 12. 导航

```dart
// 推入新页面
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const DetailPage(id: 1)),
);

// 返回
Navigator.pop(context);

// 替换当前页
Navigator.pushReplacement(context, MaterialPageRoute(...));

// 声明式路由（MaterialApp）
MaterialApp(
  routes: {
    '/': (_) => const HomePage(),
    '/detail': (_) => const DetailPage(),
  },
  initialRoute: '/',
);

// 现代推荐：go_router 包（深度链接、Web URL）
```

---

## 13. 主题 & 样式

```dart
MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    useMaterial3: true,
  ),
  darkTheme: ThemeData.dark(),
  themeMode: ThemeMode.system,
);

// 读主题
Theme.of(context).colorScheme.primary;
Theme.of(context).textTheme.titleLarge;

// Text 样式
Text('Hi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
// 或
Text('Hi', style: Theme.of(context).textTheme.headlineSmall);
```

---

## 14. 生命周期（StatefulWidget）

| 方法 | 时机 | RN 类比 |
|------|------|---------|
| `initState()` | 创建，只一次 | `useEffect([], ...)` |
| `didUpdateWidget()` | 父 props 变了 | props 变化 |
| `dispose()` | 销毁 | cleanup |
| `build()` | 每次重建 | render |

```dart
@override
void initState() {
  super.initState();       // 必须 first
  _controller = TextEditingController();
  _load();
}

@override
void dispose() {
  _controller.dispose();
  super.dispose();         // 必须 last
}
```

---

## 15. 常用类型 & 回调

| Dart | 含义 |
|------|------|
| `void Function()` | 无参无返回值 |
| `VoidCallback` | 同上（Flutter typedef） |
| `ValueChanged<T>` | `void Function(T)` |
| `AsyncCallback` | `Future<void> Function()` |
| `BuildContext` | 上下文：主题、导航、尺寸 |
| `Widget` | 所有 UI 组件基类 |
| `Key` / `ValueKey` / `GlobalKey` | 组件 identity |

---

## 16. enum & extension

```dart
enum SortMode { recent, title, created }

// 方式 A：extension 挂属性
extension SortModeLabel on SortMode {
  String get label => switch (this) {
    SortMode.recent => 'Recent',
    SortMode.title => 'Title',
    SortMode.created => 'Created',
  };
}

// 方式 B：enum 直接带字段（Dart 3+）
enum Status {
  ok('OK'),
  fail('Failed');
  const Status(this.label);
  final String label;
}

// 使用
SortMode.recent.label
SortMode.values          // 所有值
```

---

## 17. 自绘（Canvas）

```dart
CustomPaint(
  painter: MyPainter(data: points),
  child: const SizedBox.expand(),
)

class MyPainter extends CustomPainter {
  MyPainter({required this.data});
  final List<Offset> data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black..strokeWidth = 2;
    // canvas.drawLine / drawPath / drawCircle ...
  }

  @override
  bool shouldRepaint(covariant MyPainter old) => old.data != data;
}
```

≈ Web Canvas / RN Skia 底层绘制，不是声明式 `<Path>`。

---

## 18. 状态管理（手写起步 → 进阶）

| 方案 | 适用 |
|------|------|
| `setState` | 单页面、局部 state，入门首选 |
| `InheritedWidget` | 手动向下传数据（框架底层机制） |
| `Provider` / `Riverpod` | 全局/跨页面 state，最常用 |
| `Bloc` / `Cubit` | 事件驱动、大型项目 |
| `GetX` | 快速开发（争议较多） |

**起步建议：** 先用 `setState` 写通，页面间传参 + 回调；需要全局 state 再加 `riverpod` 或 `provider`。

```dart
// setState 数据流
// 父持有数据 → props 下发 → 子 onChanged 回调 → 父 setState
```

---

## 19. 包管理

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  go_router: ^14.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
```

```bash
flutter pub get          # 安装依赖
flutter pub add http     # 添加包
flutter run              # 运行
flutter analyze          # 静态检查
flutter test             # 测试
```

---

## 20. 手写代码检查清单

- [ ] 改 state 是否包了 `setState`？
- [ ] `TextEditingController` / `AnimationController` 是否在 `dispose` 里释放？
- [ ] State 里读 props 是否用 `widget.xxx`？
- [ ] 列表项是否加了 `key`？
- [ ] 能 `const` 的 Widget 是否加了 `const`？
- [ ] `Expanded` 是否在 Column/Row 内？
- [ ] 异步回调里 `setState` 前是否检查 `mounted`？
- [ ] `build` 里是否做了副作用（应放 initState / 回调里）？

```dart
// 异步 setState 安全写法
if (!mounted) return;
setState(() => _data = result);
```

---

## 21. 易混点

| 问题 | 答案 |
|------|------|
| import 文件后怎么用 | 类名直接用，无 `import X from` |
| `final obj` 能改属性吗 | 能改 `obj.field`，不能 `obj = other` |
| MaterialApp 的 `title` | 系统任务切换器名，不是 AppBar 标题 |
| `build` 能 async 吗 | 不能；异步用 FutureBuilder |
| Widget  vs Element | 你写 Widget；Flutter 内部维护 Element |
| Hot Reload 边界 | 改 `main()`/全局变量/enum 有时需 Hot Restart |

---

## 22. 最小页面模板（复制即用）

```dart
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  bool _loading = true;
  List<Item> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await api.fetchItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Page')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) => ListTile(title: Text(_items[i].name)),
            ),
    );
  }
}
```

---

## 23. 官方文档

- Dart 语言：https://dart.dev/language
- Flutter Widget 索引：https://docs.flutter.dev/ui/widgets
- Flutter 布局教程：https://docs.flutter.dev/ui/layout
- pub.dev（包搜索）：https://pub.dev
