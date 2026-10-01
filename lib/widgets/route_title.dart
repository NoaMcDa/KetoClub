import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show ApplicationSwitcherDescription, SystemChrome;
import 'package:ketoclub/utils/constants.dart';

/// The browser-tab (and task-switcher) title for a page called [page]:
/// `"Hamosad · KetoClub"`, or just the app name when [page] is null or blank
/// (issue #226).
///
/// Pure, so the format is tested without a widget tree. The separator is a
/// middle dot with a space either side; the page comes first so a row of
/// narrow tabs still shows the part that tells them apart.
String documentTitle(String? page, {String app = appName}) {
  final trimmed = page?.trim() ?? '';
  return trimmed.isEmpty ? app : '$trimmed · $app';
}

/// Keeps the document title in step with the route it sits in (issue #226).
///
/// `MaterialApp.title` is one string for the whole app, so every tab and
/// every history entry read "KetoClub". This wraps a route's content and
/// sets the title to [documentTitle] of [page] while that route is the
/// current one.
///
/// Unlike the framework's `Title` widget it does nothing on a route that has
/// been covered: routes beneath the top one stay built, and with `Title` the
/// one that happened to build last would win, leaving the wrong title after
/// a pop. Here the route that becomes current sets it, and [ModalRoute]'s
/// `isCurrent` is what triggers that rebuild.
class RouteTitle extends StatelessWidget {
  /// Titles the route around [child] with [page] (null for the bare app
  /// name).
  const new({required this.page, required this.child, super.key});

  /// The page name, already localised, or null.
  final String? page;

  /// The route content; its element is never re-created by a title change.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (isCurrent) {
      final title = documentTitle(page);
      final color = Theme.of(context).colorScheme.primary.toARGB32();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          SystemChrome.setApplicationSwitcherDescription(
            ApplicationSwitcherDescription(label: title, primaryColor: color),
          ),
        );
      });
    }
    return child;
  }
}
