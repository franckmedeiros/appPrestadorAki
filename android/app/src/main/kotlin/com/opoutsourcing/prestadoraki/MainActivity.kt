package com.opoutsourcing.prestadoraki

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth (biometria) exige FlutterFragmentActivity em vez de
// FlutterActivity, porque o prompt de biometria do Android usa
// androidx.fragment por baixo. Ver mobile/README.md.
class MainActivity : FlutterFragmentActivity()
