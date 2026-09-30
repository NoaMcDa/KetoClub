import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/menu/website/robots_txt.dart';

Uri _u(String path) => Uri.parse('https://cafe.example$path');

void main() {
  group('RobotsRules (issue #181)', () {
    test('no rules allow everything', () {
      expect(const RobotsRules().allows(_u('/menu')), isTrue);
      expect(RobotsRules.parse('').allows(_u('')), isTrue);
    });

    test('a * disallow applies to its paths only', () {
      final rules = RobotsRules.parse('User-agent: *\nDisallow: /private\n');
      expect(rules.allows(_u('/private/menu.pdf')), isFalse);
      expect(rules.allows(_u('/menu')), isTrue);
    });

    test('disallow-all refuses everything but robots.txt itself', () {
      final rules = RobotsRules.parse('User-agent: *\nDisallow: /\n');
      expect(rules.allows(_u('/')), isFalse);
      expect(rules.allows(_u('/menu')), isFalse);
      expect(rules.allows(_u('/robots.txt')), isTrue);
    });

    test('CR-only and CRLF line endings are lines too', () {
      for (final text in [
        'User-agent: *\rDisallow: /\r',
        'User-agent: *\r\nDisallow: /\r\n',
      ]) {
        expect(
          RobotsRules.parse(text).allows(_u('/menu')),
          isFalse,
          reason: text,
        );
      }
    });

    test('a group naming KetoClubBot replaces the * group', () {
      final rules = RobotsRules.parse(
        'User-agent: *\nDisallow: /\n\n'
        'User-agent: KetoClubBot\nAllow: /\nDisallow: /admin\n',
      );
      expect(rules.allows(_u('/menu')), isTrue);
      expect(rules.allows(_u('/admin/x')), isFalse);
    });

    test('our own group can refuse us while * is allowed', () {
      final rules = RobotsRules.parse(
        'User-agent: *\nAllow: /\n\nUser-agent: ketoclubbot\nDisallow: /\n',
      );
      expect(rules.allows(_u('/menu')), isFalse);
    });

    test("another bot's group is ignored", () {
      expect(
        RobotsRules.parse('User-agent: Googlebot\nDisallow: /\n')
            .allows(_u('/menu')),
        isTrue,
      );
    });

    test('consecutive user-agent lines share one group', () {
      final rules = RobotsRules.parse(
        'User-agent: Googlebot\nUser-agent: *\nDisallow: /menu\n',
      );
      expect(rules.allows(_u('/menu')), isFalse);
    });

    test('the longest match wins and a tie goes to allow', () {
      final rules = RobotsRules.parse(
        'User-agent: *\nDisallow: /menu\nAllow: /menu/food\nAllow: /menu\n',
      );
      expect(rules.allows(_u('/menu/food')), isTrue);
      expect(rules.allows(_u('/menu')), isTrue);
    });

    test('wildcards, the end anchor and the query', () {
      final rules = RobotsRules.parse(
        'User-agent: *\nDisallow: /*.pdf\$\nDisallow: /*?print=\n',
      );
      expect(rules.allows(_u('/files/menu.pdf')), isFalse);
      expect(rules.allows(_u('/files/menu.pdf?v=2')), isTrue);
      expect(rules.allows(_u('/menu?print=1')), isFalse);
    });

    test('comments, empty disallows, unknown keys and stray rules are '
        'ignored', () {
      final rules = RobotsRules.parse(
        'Disallow: /\n# comment\nUser-agent: * # all\nDisallow:\n'
        'Crawl-delay: 5\nSitemap: https://cafe.example/s.xml\nnonsense\n',
      );
      expect(rules.allows(_u('/anything')), isTrue);
    });
  });
}
