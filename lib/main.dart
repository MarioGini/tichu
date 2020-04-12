import 'package:flutter/material.dart';
import 'package:tichu/screens/login/login.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tichu',
      home: LoginPage(),
    );
  }
}
