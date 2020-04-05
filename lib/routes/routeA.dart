//lib/routes/route_A.dart

import 'package:flutter/material.dart';

class RouteA extends StatefulWidget {
  @override
  _RouteAState createState() => _RouteAState();
}

class _RouteAState extends State<RouteA> {
  CardCollection _cards;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          RaisedButton(
            onPressed: (
                // Send request that obtains cards.
                ) {},
            child: const Text(
              'Request cards',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
    ));
  }
}

class CardCollection {}
