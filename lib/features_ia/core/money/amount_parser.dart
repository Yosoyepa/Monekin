// Colombian amount parsing (T002). Owner: w-utils.
// Port of pkg/aiimport/amount.go from the ezBookkeeping fork (T001), with all its test cases.
//
// Rules: `1.234.567` = 1234567; `45.900` = 45900; `12,34` = 12.34; `1.234.567,89` = 1234567.89;
// `45,900.00` = 45900; `$ 45.900` and `COP 45.900` = 45900; a leading `-` or wrapping `( )` makes it negative.
// Returns null when the text is not an amount.
double? parseLocalizedAmount(String raw) {
  throw UnimplementedError('parseLocalizedAmount is implemented by w-utils');
}
