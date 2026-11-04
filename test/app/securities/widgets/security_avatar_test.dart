import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/securities/widgets/security_avatar.dart';

void main() {
  testWidgets('shows the ticker letters and loads no logo from a third party', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SecurityAvatar.raw(ticker: 'AAPL', name: 'Apple Inc.'),
        ),
      ),
    );

    expect(find.text('AAPL'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
