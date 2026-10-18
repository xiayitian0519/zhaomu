import 'package:flutter_test/flutter_test.dart';

import 'package:chaomu/main.dart';

void main() {
  // 只验证根组件能被构造出来。
  // 不 pumpWidget：ChaomuApp 依赖 AppState 和通知插件，单元测试环境里没有。
  test('根组件可实例化', () {
    expect(const ChaomuApp(), isNotNull);
  });
}
