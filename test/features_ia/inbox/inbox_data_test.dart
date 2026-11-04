// The structured data of an inbox item (round 3) is kept without a schema change.
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';

import 'inbox_test_helpers.dart';

void main() {
  late InboxTestEnv env;

  setUp(() async => env = await InboxTestEnv.create());
  tearDown(() => env.close());

  test('an item without data keeps the plain list of proposals', () async {
    final id = await env.service.addItem(draft([row()]));

    final stored = await env.db.select(env.db.aiInboxItems).getSingle();
    expect(stored.proposalsJson, startsWith('['));
    expect((await env.service.getItem(id))!.data, isNull);
  });

  test('the net and the difference of a statement come back as data', () async {
    final id = await env.service.addItem(
      InboxDraft(
        source: InboxSource.statement,
        sourceRef: 'nov',
        proposals: [row()],
        data: {InboxDataKeys.net: -45900.0, InboxDataKeys.difference: 0.0},
      ),
    );

    final item = (await env.service.getItem(id))!;
    expect(item.proposals.single.title, 'KFC');
    expect(item.data![InboxDataKeys.net], -45900.0);
    expect(item.data![InboxDataKeys.difference], 0.0);

    // Confirming rewrites the proposals and must keep the data.
    await env.service.confirm(id, item.proposals);
    final confirmed = (await env.service.getItem(id))!;
    expect(confirmed.data![InboxDataKeys.net], -45900.0);
  });

  test(
    'a notice waiting for the AI is finished with the proposal read',
    () async {
      final id = await env.service.addItem(
        InboxDraft(
          source: InboxSource.notification,
          sourceRef: 'com.nequi.MobileApp',
          proposals: const [],
          data: {InboxDataKeys.aiText: 'Movimiento por \$88.500'},
        ),
      );
      expect(
        (await env.service.getItem(id))!.data![InboxDataKeys.aiText],
        isNotNull,
      );

      await env.service.finishAiNotice(id, proposal: row(title: 'TIENDA'));

      final item = (await env.service.getItem(id))!;
      expect(item.proposals.single.title, 'TIENDA');
      expect(item.data?[InboxDataKeys.aiText], isNull);
    },
  );
}
