import 'package:flutter/material.dart';

class GetCards extends StatelessWidget {
  const GetCards({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold();
  }
}

class Record {
  final String name;
  final int votes;

  Record.fromMap(Map<String, dynamic> map)
    : name = map['name'] as String,
      votes = map['votes'] as int;

  @override
  String toString() => 'Record<$name:$votes>';
}
