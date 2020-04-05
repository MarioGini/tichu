import 'package:flutter/material.dart';
import 'screens/routeB.dart';
import 'data/user.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tichu',
      home: MyHomePage(),
    );
  }
}

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
