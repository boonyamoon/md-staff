import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/l10n/strings.dart';

void main() {
  const t = AppStrings(AppLanguage.th);

  test('money always carries two decimals', () {
    expect(t.money(0), '0.00');
    expect(t.money(60), '60.00');
    expect(t.money(60.5), '60.50');
    expect(t.money(60.25), '60.25');
  });

  test('thousands are grouped, above and below zero', () {
    expect(t.money(1250), '1,250.00');
    expect(t.money(1234567.8), '1,234,567.80');
    expect(t.money(-1250), '-1,250.00');
  });

  test('anything past the second decimal is rounded away', () {
    expect(t.money(10.004), '10.00');
    expect(t.money(10.006), '10.01');
    expect(t.money(999.999), '1,000.00');
    expect(t.money(-0.001), '0.00');
  });

  test('both languages write it the same way', () {
    expect(const AppStrings(AppLanguage.en).money(1250), t.money(1250));
  });
}
