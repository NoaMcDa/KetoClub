import 'package:flutter/material.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/di.dart';

void main() {
  runApp(KetoClubApp(dependencies: buildDependencies()));
}
