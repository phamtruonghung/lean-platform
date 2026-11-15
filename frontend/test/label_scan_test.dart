/// Reading a production tem (`lib/platform/label_scan.dart`).
///
/// The layouts here are the ones the plant actually prints — the two MTU tems
/// come from `planning`'s own parser, whose `LabelScan` this is a port of — plus
/// the named-key labels SAP and the plant's printouts produce. A parser that
/// reads a tem wrongly is worse than one that reads nothing, so every case that
/// must stay empty is asserted as empty.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/platform/label_scan.dart';

void main() {
  group('a tem the plant prints', () {
    test('the MTU cutting layout: Product, lot and quantity, read in place', () {
      final label = LabelScan.parse('*PLAS8NN010T0195.*095L-21614*100*PC*09*');

      expect(label.productCode, 'PLAS8NN010T0195.');
      expect(label.batch, '095L-21614');
      expect(label.quantity, '100');
      // Read from the layout, not guessed at: the person does not have to
      // confirm a tem the plant prints every day.
      expect(label.guessed, isFalse);
      expect(label.isEmpty, isFalse);
    });

    test('the Shaping layout: the quantity keeps the decimals the tem carries', () {
      final label = LabelScan.parse('*PLAS8NN010*0949-62995*1000.000*M*09*');

      expect(label.productCode, 'PLAS8NN010');
      expect(label.batch, '0949-62995');
      expect(label.quantity, '1000.000');
      expect(label.guessed, isFalse);
    });

    test('a tem with only a code carries no lot and no quantity', () {
      final label = LabelScan.parse('*PLAS8NN010*');

      expect(label.productCode, 'PLAS8NN010');
      expect(label.hasBatch, isFalse);
      expect(label.hasQuantity, isFalse);
    });

    test('a third field that is not a number is not a quantity', () {
      // `PC` is the unit on this tem, and the storage location's `09` after it:
      // neither is how much the roll holds.
      final label = LabelScan.parse('*PLAS8NN010T0195.*095L-21614*PC*M*09*');

      expect(label.productCode, 'PLAS8NN010T0195.');
      expect(label.batch, '095L-21614');
      expect(label.hasQuantity, isFalse);
    });

    test('a tem whose first field is not a code falls through, not into a Product', () {
      final label = LabelScan.parse('*cut here*');

      expect(label.isEmpty, isTrue);
      expect(label.guessed, isFalse);
    });
  });

  group('a label that names its fields', () {
    test('SAP printout keys, one pair per segment', () {
      final label = LabelScan.parse('MATNR: PLAS8NN010; CHARG: 0949-62995; MENGE: 250');

      expect(label.productCode, 'PLAS8NN010');
      expect(label.batch, '0949-62995');
      expect(label.quantity, '250');
    });

    test('keys separated by spaces rather than a separator', () {
      final label = LabelScan.parse('Code=PRD-1 Lot=LOT-9 Qty=12');

      expect(label.productCode, 'PRD-1');
      expect(label.batch, 'LOT-9');
      expect(label.quantity, '12');
      expect(label.guessed, isFalse);
    });

    test('a URL query is read like any other named label', () {
      final label = LabelScan.parse('https://example.test/tem?material=MAT-1&batch=LOT-2');

      expect(label.productCode, 'MAT-1');
      expect(label.batch, 'LOT-2');
    });

    test('a labelled quantity that is not a number stays empty', () {
      final label = LabelScan.parse('MATNR: MAT-1; MENGE: some');

      expect(label.productCode, 'MAT-1');
      expect(label.hasQuantity, isFalse);
    });
  });

  group('a label that names nothing', () {
    test('a lone code is a lot — a tem identifying only the Product is not printed', () {
      final label = LabelScan.parse('LOT-77');

      expect(label.batch, 'LOT-77');
      expect(label.hasProductCode, isFalse);
      expect(label.guessed, isTrue);
    });

    test('two codes are read by position, and flagged as a guess', () {
      final label = LabelScan.parse('PRD-1|LOT-9|12');

      expect(label.productCode, 'PRD-1');
      expect(label.batch, 'LOT-9');
      expect(label.quantity, '12');
      expect(label.guessed, isTrue);
    });

    test('free text is not a code, and fills nothing', () {
      for (final text in ['hello world', '', '   ', 'no digits here at all']) {
        expect(LabelScan.parse(text).isEmpty, isTrue, reason: 'scanned "$text"');
      }
    });
  });

  group('sameCode', () {
    test('ignores case and the trailing full stop the cutting tem carries', () {
      expect(sameCode('PLAS8NN010T0195.', 'PLAS8NN010T0195'), isTrue);
      expect(sameCode('plas8nn010t0195', 'PLAS8NN010T0195'), isTrue);
    });

    test('does not conflate two lots', () {
      expect(sameCode('LOT-1', 'LOT-11'), isFalse);
      expect(sameCode('0949-62995', '094962995'), isFalse);
    });

    test('trims what a person or a reader leaves around a code', () {
      expect(sameCode(' PRD-1 ', 'PRD-1'), isTrue);
    });
  });
}
