import 'package:flutter/material.dart';
import 'package:tichu/screens/routeB.dart';
import 'package:tichu/data/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  User user = User("");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Welcome Screen"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Enter user name'),
            Padding(
              padding: EdgeInsets.all(1.0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: "User name",
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (String str) {
                  setState(() {
                    user.userName = str;
                    Firestore.instance
                        .collection('users')
                        .document()
                        .setData({'name': user.userName, 'isReady': false});
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => RouteB(user: user)),
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
