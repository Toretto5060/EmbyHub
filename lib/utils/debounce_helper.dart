/// 防抖辅助类
/// 用于控制频繁的操作，避免在短时间内重复执行
class DebounceHelper {
  DebounceHelper._();

  /// 全局防抖记录 Map
  static final Map<String, DateTime> _lastExecutionTime = {};

  /// 默认防抖时间：10 秒
  static const Duration defaultDuration = Duration(seconds: 10);

  /// 检查是否应该执行操作（基于防抖）
  ///
  /// [key] 防抖的唯一标识
  /// [duration] 防抖时间，默认 10 秒
  ///
  /// 返回 true 表示可以执行，false 表示应该跳过
  static bool shouldExecute(String key, {Duration? duration}) {
    final effectiveDuration = duration ?? defaultDuration;
    final lastTime = _lastExecutionTime[key];
    final now = DateTime.now();

    if (lastTime == null || now.difference(lastTime) > effectiveDuration) {
      _lastExecutionTime[key] = now;
      return true;
    }

    return false;
  }

  /// 清除指定 key 的防抖记录
  static void clear(String key) {
    _lastExecutionTime.remove(key);
  }

  /// 清除所有防抖记录
  static void clearAll() {
    _lastExecutionTime.clear();
  }

  /// 获取指定 key 距离上次执行的时间
  /// 如果从未执行过，返回 null
  static Duration? getTimeSinceLastExecution(String key) {
    final lastTime = _lastExecutionTime[key];
    if (lastTime == null) return null;
    return DateTime.now().difference(lastTime);
  }

  /// 检查指定 key 是否在防抖期内
  static bool isInDebounce(String key, {Duration? duration}) {
    final effectiveDuration = duration ?? defaultDuration;
    final lastTime = _lastExecutionTime[key];
    if (lastTime == null) return false;
    return DateTime.now().difference(lastTime) <= effectiveDuration;
  }
}
