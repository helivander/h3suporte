import 'dart:math';

import 'package:flutter_hbb/models/ai_agent_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screenshots are capped on the long edge and never upscaled', () {
    expect(aiScaledSize(1920, 1080), const Point(1280, 720));
    expect(aiScaledSize(1080, 1920), const Point(720, 1280));
    expect(aiScaledSize(1024, 768), const Point(1024, 768));
  });

  test('model coordinates map to the remote display, including its origin',
      () {
    Point<int> map(num x, num y) => aiToRemotePoint(x, y,
        sentWidth: 1280,
        sentHeight: 720,
        left: 1920,
        top: 0,
        width: 2560,
        height: 1440);
    expect(map(0, 0), const Point(1920, 0));
    expect(map(640, 360), const Point(3200, 720));
    expect(map(5000, -3), const Point(1920 + 2558, 0));
  });

  test('key combos become session key names and modifier flags', () {
    final save = parseAiKeyCombo('ctrl+s')!;
    expect(save.name, 'VK_S');
    expect([save.ctrl, save.alt, save.shift, save.command],
        [true, false, false, false]);

    expect(parseAiKeyCombo('Return')!.name, 'VK_RETURN');
    expect(parseAiKeyCombo('Page_Down')!.name, 'VK_NEXT');
    expect(parseAiKeyCombo('F5')!.name, 'VK_F5');

    final switcher = parseAiKeyCombo('alt+Tab')!;
    expect(switcher.name, 'VK_TAB');
    expect(switcher.alt, isTrue);

    final start = parseAiKeyCombo('super')!;
    expect(start.name, 'Meta');
    expect(start.command, isFalse);

    final zoomIn = parseAiKeyCombo('ctrl++')!;
    expect(zoomIn.name, '+');
    expect(zoomIn.ctrl, isTrue);

    expect(parseAiKeyCombo('ctrl+alt+Delete')!.name, 'CTRL_ALT_DEL');
    expect(parseAiKeyCombo('NoSuchKey'), isNull);
    expect(parseAiKeyCombo('hyper+a'), isNull);
  });
}
