/// What a scanned label said — the plant's tem, read into the fields a
/// Non-conformance records.
///
/// A shop-floor reader is a keyboard: it types the symbol it read into the
/// field it was pointed at (`widgets/app_scan_field.dart`). The problem this
/// file answers is that a production tem is not one value — the same symbol
/// carries the Product's own code, the lot it came from and how much the roll
/// holds, and a person who had to retype those three from the tem in their hand
/// would be transcribing, which is where the floor's mistakes come from.
///
/// The reading is the one `planning` already does for its own stock scan
/// (`production-planning/lib/core/obs_stock.dart`, `LabelScan`), because a tem
/// is the plant's, not one application's: the named keys are the ones SAP and
/// the plant's own labels put on a symbol, and the two tem layouts the plant
/// prints are read by position, not guessed at.
///
/// **Nothing says what a tem's symbol encodes**, so this parser is deliberately
/// tolerant and admits when it guessed: [guessed] means the fields came from
/// position rather than from named keys, and the person must confirm them
/// before the record is filed. Anything it cannot read it leaves empty rather
/// than filling a field with a number that is not the thing that field names.
library;

/// What a scanned label said, field by field.
///
/// Every value is the label's own text, trimmed and unquoted, never reformatted:
/// the quantity a tem carries is `1000.000` on one layout and `100` on the
/// other, and rewriting that is neither this class's job nor safe for a
/// quantity that is later compared with what was found.
class LabelScan {
  const LabelScan({
    required this.raw,
    this.productCode,
    this.batch,
    this.quantity,
    this.guessed = false,
  });

  /// The code as the reader delivered it, before anything was read out of it.
  final String raw;

  /// The Product's own code (`PLAS8NN010T0195.` on the MTU cutting tem), absent
  /// when the label names no Product.
  final String? productCode;

  /// The lot or batch number, absent when the label names none.
  final String? batch;

  /// How much the label says it holds, as the label wrote it — `100`, `1000.000`.
  final String? quantity;

  /// Whether the fields were read by position instead of from named keys, which
  /// makes them something the person confirms rather than something the label
  /// states.
  final bool guessed;

  bool get hasProductCode => (productCode ?? '').isNotEmpty;
  bool get hasBatch => (batch ?? '').isNotEmpty;
  bool get hasQuantity => (quantity ?? '').isNotEmpty;

  /// Nothing was readable: the scan is a code the form cannot use, and saying so
  /// is better than leaving three fields untouched with no explanation.
  bool get isEmpty => !hasProductCode && !hasBatch && !hasQuantity;

  /// Key names seen on plant labels and SAP printouts for the Product's code.
  static const Set<String> _productKeys = {
    'material',
    'materialnr',
    'materialno',
    'materialnumber',
    'matnr',
    'mat',
    'artnr',
    'artikel',
    'artikelnummer',
    'item',
    'code',
    'mavt',
    'mavattu',
    'product',
    'productno',
    'productcode',
    'sanpham',
    'mahang',
  };

  /// Key names for the lot. `charge`/`charg` are SAP's own (German) name for it
  /// and are what the plant's printouts carry.
  static const Set<String> _batchKeys = {
    'batch',
    'batchno',
    'batchnumber',
    'batchid',
    'charge',
    'charg',
    'lot',
    'lotnr',
    'lotno',
    'loso',
    'solo',
  };

  /// Key names for the quantity on the label.
  static const Set<String> _quantityKeys = {
    'menge',
    'qty',
    'qnt',
    'quantity',
    'amount',
    'soluong',
    'sl',
  };

  /// Reads [text] into its fields.
  ///
  /// Separators first, then named keys, then the plant's own tem layout, then
  /// position as a last resort. The order matters: a label that names its fields
  /// is never read by position, and a tem whose layout this file knows is never
  /// guessed at.
  static LabelScan parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return const LabelScan(raw: '');

    String? productCode;
    String? batch;
    String? quantity;

    // A label may put several pairs on one line (`MATNR: X  CHARG: Y`): mark a
    // boundary before every `name:` / `name=` so each pair becomes its own
    // segment. A URL's query is split on `?` for the same reason.
    final marked = raw
        .replaceAll('?', ';')
        .replaceAllMapped(
          RegExp(r'\s+(?=[A-Za-zÀ-ỹ][A-Za-zÀ-ỹ0-9_\-.]{0,20}\s*[:=])'),
          (_) => ';',
        );
    final segments = <String>[];
    for (final part in marked.split(RegExp(r'[;&|\r\n\t]+'))) {
      final segment = part.trim();
      if (segment.isEmpty) continue;
      segments.add(segment);
      final match = RegExp(
        r'^([A-Za-zÀ-ỹ][A-Za-zÀ-ỹ0-9 _\-./]{0,24})\s*[:=]\s*(.+)$',
      ).firstMatch(segment);
      if (match == null) continue;
      final key = _normaliseKey(match.group(1)!);
      final value = _cleanValue(match.group(2)!);
      if (value.isEmpty) continue;
      if (_productKeys.contains(key) && productCode == null) productCode = value;
      if (_batchKeys.contains(key) && batch == null) batch = value;
      if (_quantityKeys.contains(key) && quantity == null && _looksLikeQty(value)) {
        quantity = value;
      }
    }
    if (productCode != null || batch != null || quantity != null) {
      return LabelScan(
        raw: raw,
        productCode: productCode,
        batch: batch,
        quantity: quantity,
      );
    }

    // The tems the plant prints for a roll — MTU cutting and Shaping — carry a
    // DataMatrix symbol with a fixed layout, so its fields are read in place.
    final tem = _parseTem(raw);
    if (tem != null) return tem;

    // No named key and no known layout: drop a URI's scheme part and any token
    // that is obviously not a code, then read what is left by position.
    final tokens = [
      for (final segment in segments)
        if (!segment.contains('://')) segment,
    ];
    if (tokens.length == 1 && tokens.first.contains('/')) {
      final parts = tokens.first.split('/');
      if (parts.length == 2 &&
          parts[0].trim().isNotEmpty &&
          parts[1].trim().isNotEmpty) {
        return LabelScan(
          raw: raw,
          productCode: _cleanValue(parts[0]),
          batch: _cleanValue(parts[1]),
          guessed: true,
        );
      }
    }
    if (tokens.length == 1) {
      final value = _cleanValue(tokens.first);
      if (!_looksLikeCode(value)) return LabelScan(raw: raw);
      // A lone code on a label is a lot: a tem that identifies only the Product
      // is not printed, while a lot sticker with no Product on it is.
      return LabelScan(raw: raw, batch: value, guessed: true);
    }
    if (tokens.length >= 2) {
      final product = _cleanValue(tokens[0]);
      final lot = _cleanValue(tokens[1]);
      // Only a pair of plausible codes is worth guessing: free text on the label
      // must not turn into a Product and a lot the plant never had.
      if (!_looksLikeCode(product) || !_looksLikeCode(lot)) {
        return LabelScan(raw: raw);
      }
      final third = tokens.length > 2 ? _cleanValue(tokens[2]) : '';
      return LabelScan(
        raw: raw,
        productCode: product,
        batch: lot,
        quantity: _looksLikeQty(third) ? third : null,
        guessed: true,
      );
    }
    return LabelScan(raw: raw);
  }

  /// A plant code — Product or lot — always carries at least one digit.
  static bool _looksLikeCode(String value) =>
      value.isNotEmpty && RegExp(r'[0-9]').hasMatch(value);

  /// A quantity is digits with at most one decimal separator — `100`,
  /// `1000.000`, `12,5` — and nothing else, so a storage location's `09` or a
  /// unit's `PC` cannot become one.
  static bool _looksLikeQty(String value) =>
      RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(value.trim());

  /// Reads the layout of the tem the plant prints for a roll: `*`-separated
  /// fields, `*mã*lô*số lượng*đơn vị*kho*`, ending in the closing `*`.
  ///
  /// The two production labels decode as
  /// `*PLAS8NN010T0195.*095L-21614*100*PC*09*` (MTU cutting) and
  /// `*PLAS8NN010*0949-62995*1000.000*M*09*` (Shaping): the Product's code
  /// first, the lot second, then the quantity, its unit and the storage
  /// location. Returns null for anything that is not that shape, so an unknown
  /// label still falls through to the positional reading.
  ///
  /// A tem with only a mã carries no lot, and that must never become a
  /// quantity or a lot: the record would then name a batch the plant never
  /// made.
  static LabelScan? _parseTem(String raw) {
    if (raw.length < 3 || !raw.startsWith('*') || !raw.endsWith('*')) return null;
    final fields = [
      for (final field in raw.split('*'))
        if (field.trim().isNotEmpty) _cleanValue(field),
    ];
    if (fields.isEmpty) return null;
    final productCode = fields.first;
    if (!_looksLikeCode(productCode)) return null;
    final batch = fields.length > 1 ? fields[1] : null;
    if (batch != null && !_looksLikeCode(batch)) return null;
    final third = fields.length > 2 ? fields[2] : '';
    return LabelScan(
      raw: raw,
      productCode: productCode,
      batch: batch,
      quantity: _looksLikeQty(third) ? third : null,
    );
  }

  static String _normaliseKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Strips what a label puts around a value rather than in it: a trailing
  /// separator the field was split on, a wrapping pair of quotes.
  static String _cleanValue(String value) {
    var v = value.trim();
    while (v.endsWith(';') || v.endsWith(',') || v.endsWith(')')) {
      v = v.substring(0, v.length - 1).trim();
    }
    if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
      v = v.substring(1, v.length - 1).trim();
    }
    return v;
  }
}

/// Whether two codes name the same record.
///
/// A code is compared the way the plant writes it, not the way this application
/// happens to store it: case does not distinguish two codes, and the MTU cutting
/// tem carries a trailing full stop after the Product's code that the register
/// does not (`PLAS8NN010T0195.` on the label, `PLAS8NN010T0195` in the
/// catalogue). Everything else is compared exactly — a lot number's own hyphens
/// are part of it.
bool sameCode(String left, String right) => _codeKey(left) == _codeKey(right);

String _codeKey(String value) {
  var key = value.trim().toUpperCase();
  while (key.endsWith('.') || key.endsWith(' ')) {
    key = key.substring(0, key.length - 1);
  }
  return key;
}
