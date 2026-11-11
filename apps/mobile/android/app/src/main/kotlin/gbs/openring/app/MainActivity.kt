package gbs.openring.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

private const val PRIVACY_LINK = "openring://app/privacy"
private val PRIVACY_ACTIONS = setOf(
    "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE",
    Intent.ACTION_VIEW_PERMISSION_USAGE,
)

// The health plugin requests Health Connect permissions through
// registerForActivityResult, which needs a ComponentActivity.
class MainActivity : FlutterFragmentActivity() {
    // Result launchers must be registered before the activity starts.
    private lateinit var permissions: PermissionsChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        routePrivacyLink(intent)
        permissions = PermissionsChannel(this)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        routePrivacyLink(intent)
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        permissions.attach(flutterEngine.dartExecutor.binaryMessenger)
        HealthSettingsChannel(this).attach(flutterEngine.dartExecutor.binaryMessenger)
    }

    // Flutter's deep linking reads only the intent data, so the Health Connect
    // actions, which carry none, get the policy route written in.
    private fun routePrivacyLink(intent: Intent?) {
        if (intent?.action !in PRIVACY_ACTIONS) return
        intent?.data = Uri.parse(PRIVACY_LINK)
    }
}
