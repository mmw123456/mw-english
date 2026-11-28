import 'package:flutter/foundation.dart';

/// 全局轻量信号：只用于「某个东西改过了，相关页面要重读」。
///
/// 为什么需要它：四个 Tab 页都 keep-alive（v0.7.3），从设置页 / 导入页返回、
/// 再切回学习页时页面不会重建，也不会重新读库。改完每日目标或导入了一批词，
/// 首页的环、状态行、当天配额与「全部词汇」必须立刻跟上，靠的就是这两个计数器。
///
/// 只放「变了」这件事，不放业务数据 —— 页面收到通知后自己去 DAO 读。
/// 不是全局状态管理，别把值塞进来。
class AppSignals {
  AppSignals._();

  /// 设置变更计数。任何页面都可以监听，收到后自行重读需要的设置。
  static final ValueNotifier<int> settingsChanged = ValueNotifier<int>(0);

  /// 词库变更计数（v0.9.0）：导入词表、按批撤销这类改动自加词数量的操作。
  ///
  /// 和 [settingsChanged] 分开是因为语义不同：一个是「偏好变了」，一个是
  /// 「我的词表变了」。页面通常两个都要听，用 `Listenable.merge` 合成一个。
  static final ValueNotifier<int> libraryChanged = ValueNotifier<int>(0);

  /// 设置写库成功后调用。
  static void settingsUpdated() => settingsChanged.value++;

  /// 自加词 / 词库变化后调用。
  static void libraryUpdated() => libraryChanged.value++;
}
