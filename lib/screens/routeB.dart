import 'package:flutter/material.dart';
import 'package:tichu/data/user.dart';
import 'package:tichu/services/getCards.dart';

class RouteB extends StatelessWidget {
  final User user;

  RouteB({Key key, @required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text("Hi " + user.userName + ", please obtain your random cards"),
          RaisedButton(
            child: const Text(
              'Request cards',
              style: TextStyle(fontSize: 20),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => GetCards()),
              );
            },
          ),
        ],
      ),
    ));
  }
}
