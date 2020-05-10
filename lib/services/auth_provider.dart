import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_login/flutter_facebook_login.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final GoogleSignIn googleSignIn = GoogleSignIn();
final FacebookLogin facebookLogin = FacebookLogin();
FirebaseUser _user;

String name;
String email;
String imageUrl;

Future<String> signInAnon() async {
  if (_auth.currentUser() == null) {
    final authResult = await _auth.signInAnonymously();
    _user = authResult.user;
    assert(await _user.getIdToken() != null);
  }

  return 'anonymous sign-in success: $_user';
}

Future<String> signInWithGoogle() async {
  final googleSignInAccount = await googleSignIn.signIn();
  final googleSignInAuthentication = await googleSignInAccount.authentication;
  final credential = GoogleAuthProvider.getCredential(
    accessToken: googleSignInAuthentication.accessToken,
    idToken: googleSignInAuthentication.idToken,
  );

  final authResult = await _auth.signInWithCredential(credential);
  _user = authResult.user;

  assert(!_user.isAnonymous);
  assert(await _user.getIdToken() != null);

  final currentUser = await _auth.currentUser();
  assert(_user.uid == currentUser.uid);

  assert(_user.email != null);
  assert(_user.displayName != null);
  assert(_user.photoUrl != null);

  name = _user.displayName;
  email = _user.email;
  imageUrl = _user.photoUrl;

  // Only taking the first part of the name, i.e., First Name
  if (name.contains(' ')) {
    name = name.substring(0, name.indexOf(' '));
  }

  return 'signInWithGoogle succeeded: $_user';
}

Future<String> signInWithFacebook() async {
  facebookLogin.loginBehavior = FacebookLoginBehavior.webViewOnly;
  final result = await facebookLogin.logIn(['email']);
  final token = result.accessToken.token;
  var credential = FacebookAuthProvider.getCredential(accessToken: token);
  final authResult = await _auth.signInWithCredential(credential);
  _user = authResult.user;

  assert(!_user.isAnonymous);
  assert(await _user.getIdToken() != null);

  final currentUser = await _auth.currentUser();
  assert(_user.uid == currentUser.uid);

  assert(_user.email != null);
  assert(_user.displayName != null);
  assert(_user.photoUrl != null);

  name = _user.displayName;
  email = _user.email;
  imageUrl = _user.photoUrl;

  // Only taking the first part of the name, i.e., First Name
  if (name.contains(' ')) {
    name = name.substring(0, name.indexOf(' '));
  }

  return 'signInWithGoogle succeeded: $_user';
}

void signOutFacebook() async {
  await facebookLogin.logOut();
  await _auth.signOut();
  _user = null;
}

void signOutGoogle() async {
  await googleSignIn.signOut();
  await _auth.signOut();
  _user = null;
}
