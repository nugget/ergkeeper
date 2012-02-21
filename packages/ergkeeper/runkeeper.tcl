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

proc runkeeper_request {method} {
	set uri "$::config(rkapi_base_url)$method"
	set headers [list Authorization "Bearer $::user(runkeeper_oauth_token)" Accept application/vnd.com.runkeeper.User+json]

	# puts "<h1>get $uri</h1>"

	::http::register https 443 ::tls::socket
    set fp [::http::geturl $uri -timeout 15000 -headers $headers]
	set status [::http::status $fp]
	set ncode [::http::ncode $fp]
	set err [::http::error $fp]
	set formdata [string trim [::http::data $fp]]
	upvar #0 $fp state
	# parray state
	::http::cleanup $fp

    # Extract the access token.
    if {$status != "ok" || $ncode != 200} {
        puts "Major Fail to retrieve method: $status / $ncode / $formdata / $err"
		return
    }

    set jsonkv [::yajl::json2dict $formdata]
    array set response $jsonkv
	# parray response

	return [array get response]

}

package provide ergkeeper 1.0
