import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/utils/file_category.dart';

void main() {
  group('FileCategoryRule parsing', () {
    test('parses valid rule JSON and normalizes extensions', () {
      final rule = FileCategoryRule.tryParse(
        '{"extensions":[".MP4","mkv "],"subdirectory":"Videos/"}',
      );

      expect(rule, isNotNull);
      expect(rule!.extensions, {'mp4', 'mkv'});
      expect(rule.subdirectory, 'Videos');
    });

    test('rejects malformed or traversal rules', () {
      expect(FileCategoryRule.tryParse('not json'), isNull);
      expect(
        FileCategoryRule.tryParse('{"extensions":[],"subdirectory":"a"}'),
        isNull,
      );
      expect(
        FileCategoryRule.tryParse(
          '{"extensions":["mp4"],"subdirectory":"../x"}',
        ),
        isNull,
      );
      for (final subdirectory in <String>[
        '.',
        '..',
        '/outside',
        'C:/outside',
        'safe/invalid:name',
      ]) {
        expect(
          FileCategoryRule.tryParse(
            '{"extensions":["mp4"],"subdirectory":"$subdirectory"}',
          ),
          isNull,
          reason: 'accepted unsafe subdirectory $subdirectory',
        );
      }
    });

    test('parseFileCategoryRules caps at the maximum', () {
      final raw = List.generate(
        maxFileCategoryRules + 5,
        (i) => '{"extensions":["e$i"],"subdirectory":"d$i"}',
      );

      expect(parseFileCategoryRules(raw).length, maxFileCategoryRules);
    });
  });

  group('categorySubdirFor', () {
    final rules = parseFileCategoryRules([
      '{"extensions":["mp4","mkv"],"subdirectory":"Videos"}',
      '{"extensions":["zip"],"subdirectory":"Archives"}',
    ]);

    test('routes matching URIs to their subdirectory', () {
      expect(
        categorySubdirFor('https://example.com/movie.mp4?token=1', rules),
        'Videos',
      );
      expect(
        categorySubdirFor('ftp://example.com/files/big.ZIP', rules),
        'Archives',
      );
    });

    test('returns null for unmatched extensions and non-download URIs', () {
      expect(categorySubdirFor('https://example.com/page.html', rules), isNull);
      expect(categorySubdirFor('magnet:?xt=urn:btih:abc', rules), isNull);
      expect(categorySubdirFor('https://example.com/', rules), isNull);
      expect(
        categorySubdirFor('https://example.com/file.zip', const []),
        isNull,
      );
    });

    test('routes the first matching URI in a multiline value', () {
      const uris = '''
        https://example.com/readme.txt

        https://example.com/archive.zip
        https://example.com/movie.mp4
      ''';

      expect(categorySubdirForUris(uris, rules), 'Archives');
    });

    test('returns null when no URI in a multiline value matches', () {
      const uris = '''
        magnet:?xt=urn:btih:abc
        https://example.com/readme.txt
      ''';

      expect(categorySubdirForUris(uris, rules), isNull);
      expect(categorySubdirForUris('\r\n  \n', rules), isNull);
    });
  });
}
