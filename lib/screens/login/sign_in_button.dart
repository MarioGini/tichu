import 'package:flutter/material.dart';
import '../../services/auth_provider.dart';

class SignInGoogleButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () {
        // signInAnon().whenComplete(() {
        //   Navigator.of(context).push(
        //     MaterialPageRoute(
        //       builder: (context) {
        //         return Scaffold();
        //       },
        //     ),
        //   );
        // });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                'Sign in with Google',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// Widget signInFacebookButton() {
//   return OutlineButton(
//     splashColor: Colors.grey,
//     onPressed: () {
//       signInWithFacebook().whenComplete(() {
//         Navigator.of(context).push(
//           MaterialPageRoute(
//             builder: (context) {
//               return FirstScreen();
//             },
//           ),
//         );
//       });
//     },
//     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
//     highlightElevation: 0,
//     borderSide: BorderSide(color: Colors.grey),
//     child: Padding(
//       padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: <Widget>[
//           Padding(
//             padding: const EdgeInsets.only(left: 10),
//             child: Text(
//               'Sign in with Facebook',
//               style: TextStyle(
//                 fontSize: 20,
//                 color: Colors.grey,
//               ),
//             ),
//           )
//         ],
//       ),
//     ),
//   );
// }
