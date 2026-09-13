import 'package:flutter/material.dart';
import 'package:ketoclub/utils/constants.dart';

/// The first screen: locate, search, or paste a venue link
/// (architecture.md §6.5, §6.6).
///
/// Placeholder until build-order step 4 lands the real screen.
class VenueSearchScreen extends StatelessWidget {
  /// Creates the venue search screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text(appName)));
  }
}
