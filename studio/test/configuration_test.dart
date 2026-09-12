import 'package:flutter_test/flutter_test.dart';
import 'package:macro_wheel_studio/models/configuration.dart';
import 'package:macro_wheel_studio/services/configuration_validator.dart';

Configuration _valid() {
  return Configuration.empty(scriptsFolder: 'scripts').withPage(
    'edit',
    const PageConfig(
      profiles: [
        Profile(
          id: 'p1',
          name: 'Default',
          isDefault: true,
          innerRing: [
            InnerSlice(
              id: 's1',
              type: 'command',
              label: 'Blade',
              command: CommandRef(
                type: 'builtin',
                commandId: 'builtin.edit.blade',
              ),
            ),
            InnerSlice(
              id: 's2',
              type: 'category',
              label: 'Effects',
              category: Category(
                id: 'c1',
                name: 'Effects',
                outerCommands: [
                  CommandRef(
                    type: 'addEffect',
                    effectPayload: 'Glow OFX',
                    effectName: 'Glow',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  group('Configuration', () {
    test('round-trips through JSON', () {
      final original = _valid();
      final restored =
          Configuration.fromJsonString(original.toJsonString());
      expect(restored.toJsonString(), equals(original.toJsonString()));
    });

    test('collects referenced script ids', () {
      final config = _valid().withPage(
        'color',
        const PageConfig(
          profiles: [
            Profile(
              id: 'p2',
              name: 'Default',
              isDefault: true,
              innerRing: [
                InnerSlice(
                  id: 's3',
                  type: 'command',
                  command: CommandRef(type: 'script', scriptId: 'abc-123'),
                ),
              ],
            ),
          ],
        ),
      );
      expect(config.referencedScriptIds, contains('abc-123'));
    });
  });

  group('ConfigurationValidator', () {
    test('accepts a well-formed configuration', () {
      expect(ConfigurationValidator.errors(_valid()), isEmpty);
    });

    test('rejects a page with no default profile', () {
      final config = Configuration.empty(scriptsFolder: 's').withPage(
        'edit',
        const PageConfig(
          profiles: [
            Profile(
              id: 'p1',
              name: 'Only',
              isDefault: false,
              innerRing: [],
            ),
          ],
        ),
      );
      final issues = ConfigurationValidator.errors(config);
      expect(issues.any((i) => i.message.contains('default profile')), isTrue);
    });

    test('rejects more than 8 inner slices', () {
      final slices = List.generate(
        kMaxInnerSlices + 1,
        (i) => InnerSlice(
          id: 's$i',
          type: 'command',
          command:
              const CommandRef(type: 'builtin', commandId: 'builtin.edit.blade'),
        ),
      );
      final config = Configuration.empty(scriptsFolder: 's').withPage(
        'edit',
        PageConfig(
          profiles: [
            Profile(id: 'p1', name: 'D', isDefault: true, innerRing: slices),
          ],
        ),
      );
      expect(
        ConfigurationValidator.errors(config)
            .any((i) => i.message.contains('inner slices')),
        isTrue,
      );
    });

    test('rejects an unknown page', () {
      final config =
          Configuration.empty(scriptsFolder: 's').withPage('bogus', const PageConfig(profiles: []));
      expect(
        ConfigurationValidator.errors(config)
            .any((i) => i.message.contains('Not a Resolve page')),
        isTrue,
      );
    });
  });
}