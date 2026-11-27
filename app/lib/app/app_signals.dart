import 'package:flutter/foundation.dart';

/// 全局轻量信号：只用于「某个设置改过了，相关页面要重读」。
///
/// 为什么需要它：四个 Tab 页都 keep-alive（v0.7.3），从设置页返回、再切回
/// 学习页时页面不会重建，也不会重新读库。设置页改完每日目标后，首页的环、
/// 状态行和当天配额必须立刻跟上，靠的就是这个计数器。
///
/// 只放「变了」这件事，不放业务数据 —— 页面收到通知后自己去 DAO 读。
/// 不是全局状态管理，别把值塞进来。
class AppSignals {
  AppSignals._();

  /// 设置变更计数。任何页面都可以监听，收到后自行重读需要的设置。
  static final ValueNotifier<int> settingsChanged = ValueNotifier<int>(0);

  /// 设置写库成功后调用。
  static void settingsUpdated() => settingsChanged.value++;
}
