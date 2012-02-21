proc runkeeper_login_button {} {
	set buf ""

	set args(client_id)		"$::config(rkapi_client_id)"
	set args(redirect_uri)	"$::config(base_url)login"
	set args(response_type)	"code"
	set args(state)			"runkeeper"

	foreach f [array names args] {
		lappend arglist "$f=$args($f)"
	}

	append buf {<script src="http://static1.runkeeper.com/script/runkeeper_assets.js"></script>}
	append buf {<a id="rk_login-blue-black" class="rk_webButtonWithText200" href="}
	append buf "$::config(rkapi_auth_url)?"
	append buf [join $arglist "&"]
	append buf {" title="Login with RunKeeper, powered by the Health Graph"></a>}
}

package provide ergkeeper 1.0
