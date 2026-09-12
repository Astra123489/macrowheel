import 'package:flutter_test/flutter_test.dart';
import 'package:macro_wheel_studio/services/shortcut_parser.dart';

const _sample = '''
editBlade := B
editInsertOverwriteActionInsert := F9
editSearchInEffects := Shift+Space
FusionWidget.fuHotkey_GLViewer_Viewer_Channel{chan = 2, toggle = true} := B
fileSaveProject := Ctrl+S | Ctrl+Shift+S
editUndo := Ctrl+Z | `
''';

void main() {
  group('ShortcutParser', () {
    test('parses command ids and sequences', () {
      final parser = ShortcutParser.parse(_sample);
      expect(parser.sequencesFor('editBlade'), equals(['B']));
      expect(parser.sequencesFor('editInsertOverwriteActionInsert'),
          equals(['F9']));
    });

    test('splits alternative sequences on |', () {
      final parser = ShortcutParser.parse(_sample);
      expect(parser.sequencesFor('fileSaveProject'),
          equals(['Ctrl+S', 'Ctrl+Shift+S']));
    });

    test('resolves the effect search shortcut', () {
      final parser = ShortcutParser.parse(_sample);
      expect(parser.hasSearchEffectsBinding, isTrue);
      expect(parser.searchEffectsShortcut, equals('Shift+Space'));
    });

    test('reports no search binding when absent', () {
      final parser = ShortcutParser.parse('editBlade := B\n');
      expect(parser.hasSearchEffectsBinding, isFalse);
      expect(parser.searchEffectsShortcut, isNull);
    });

    test('detects commands sharing a sequence', () {
      final parser = ShortcutParser.parse(_sample);
      // Both editBlade and the Fusion channel toggle use B.
      expect(parser.commandsUsing('B'), hasLength(2));
    });

    test('detects conflicts against studio hotkeys', () {
      final parser = ShortcutParser.parse(_sample);
      final conflicts = parser.conflictsWith({
        'Wheel activation': 'Shift+Space',
        'Profile cycle': 'Ctrl+Alt+P',
      });
      expect(conflicts.keys, contains('Wheel activation'));
      expect(conflicts['Wheel activation'], contains('editSearchInEffects'));
      expect(conflicts.containsKey('Profile cycle'), isFalse);
    });

    test('rejects empty input', () {
      expect(() => ShortcutParser.parse('  \n'),
          throwsA(isA<FormatException>()));
    });

    test('ignores unbound commands and comments', () {
      final parser = ShortcutParser.parse('# comment\neditBlade := B\nfoo := \n');
      expect(parser.sequencesFor('foo'), isEmpty);
    });
  });
}