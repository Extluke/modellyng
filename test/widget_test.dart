import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/app.dart';

void main() {
  testWidgets('welcome screen enters the research workspace', (tester) async {
    await tester.pumpWidget(const ModellyngApp());

    expect(
      find.text('Ubah paper menjadi\npengetahuan yang\ndapat diverifikasi.'),
      findsOneWidget,
    );
    final getStarted = find.byKey(const Key('get-started-button'));
    await tester.ensureVisible(getStarted);
    await tester.tap(getStarted);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Selamat datang, Aditya'), findsOneWidget);
    expect(find.text('Proyek terbaru'), findsOneWidget);
  });

  testWidgets('dashboard exposes the primary MVP actions', (tester) async {
    await tester.pumpWidget(const ModellyngApp(skipWelcome: true));

    expect(find.text('Proyek baru'), findsWidgets);
    expect(find.text('12 hasil AI menunggu verifikasi Anda'), findsOneWidget);
    expect(find.text('Paper dianalisis'), findsOneWidget);
  });
}
