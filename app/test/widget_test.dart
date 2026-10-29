import 'package:flutter_test/flutter_test.dart';
import 'package:osiris_camera_vision/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OsirisCameraVisionApp());
    expect(find.byType(OsirisCameraVisionApp), findsOneWidget);
  });
}
