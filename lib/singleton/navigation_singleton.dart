import 'package:flutter/material.dart';

class Singleton {
  static final Singleton _singleton = Singleton._internal();

  factory Singleton() {
    return _singleton;
  }

  Singleton._internal();

  GlobalKey<NavigatorState> navigatorStateKey = GlobalKey<NavigatorState>();
}
