//lib/routes/route_B.dart

import 'package:flutter/material.dart';

class RouteB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text("Welcome to Route B"),
        ],
      ),
    ));
  }
}
