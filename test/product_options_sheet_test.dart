import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/menu_dto.dart';
import 'package:md_staff/features/menu/menu_controller.dart';
import 'package:md_staff/features/menu/product_options_sheet.dart';

/// Enough groups that the note is below the fold, as it is for a dish with a few choices.
final _detail = ProductDetail(
  id: 'p1',
  productName: 'Basil pork',
  skus: const [MenuSku(id: 'sku', skuName: 'Plate', defaultPrice: 60)],
  optionGroups: [
    for (var g = 1; g <= 3; g++)
      ProductOptionGroup(
        id: 'g$g',
        groupName: 'Group $g',
        options: [for (var o = 1; o <= 6; o++) ProductOption(id: 'o$g$o', optionName: 'Option $g.$o')],
      ),
  ],
);

const _product = MenuProduct(id: 'p1', productName: 'Basil pork');

void main() {
  Future<void> openSheet(WidgetTester tester, Size screen, {double top = 47}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: top);
    tester.view.viewPadding = FakeViewPadding(top: top);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productDetailProvider.overrideWith((ref, id) async => _detail)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProductOptionsSheet(context, product: _product),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapNote(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byType(TextField),
      120,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
  }

  Future<void> raiseKeyboard(WidgetTester tester, double height) async {
    // In steps, as a real keyboard slides up.
    for (final part in [0.25, 0.5, 0.75, 1.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: height * part);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
  }

  for (final (name, screen, top, keyboard) in [
    ('a current iPhone', const Size(390, 844), 47.0, 336.0),
    ('a small phone', const Size(320, 568), 20.0, 260.0),
  ]) {
    testWidgets('the note and the add button stay above the keyboard on $name', (tester) async {
      await openSheet(tester, screen, top: top);
      await tapNote(tester);

      await raiseKeyboard(tester, keyboard);

      final keyboardTop = screen.height - keyboard;
      final field = tester.getRect(find.byType(TextField));
      final list = tester.getRect(find.byType(ListView));
      final add = tester.getRect(find.byType(FilledButton));
      expect(add.bottom, lessThanOrEqualTo(keyboardTop));
      expect(field.bottom, lessThanOrEqualTo(list.bottom));
      expect(field.top, greaterThanOrEqualTo(list.top));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the keyboard closes from its own done key', (tester) async {
    await openSheet(tester, const Size(390, 844));
    await tapNote(tester);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(editable.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('and from a tap elsewhere', (tester) async {
    await openSheet(tester, const Size(390, 844));
    await tapNote(tester);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));

    await tester.tap(find.text('Basil pork'));
    await tester.pumpAndSettle();

    expect(editable.widget.focusNode.hasFocus, isFalse);
  });
}
