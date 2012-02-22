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

proc runkeeper_request {method {token ""}} {
	set success		0
	set details		"Unknown"
	array set reponse {}

	if {$token == "" && [info exists ::user(runkeeper_oauth_token)] && $::user(runkeeper_oauth_token) != ""} {
		set token $::user(runkeeper_oauth_token)
	}

	if {$token == ""} {
		return [list $success [array get response] "No token available"]
	}

	set uri "$::config(rkapi_base_url)$method"
	set headers [list Authorization "Bearer $token"]

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

	set details "uri:$uri status:$status ncode:$ncode data:$formdata err:$err"

    set jsonkv [::yajl::json2dict $formdata]
	# puts "<pre>$jsonkv</pre>"
    array set response $jsonkv

	# parray response

	set success 1

	return [list $success [array get response] $details]
}

proc runkeeper_bind_user {token} {

	pg_select $::db "SELECT * FROM users WHERE runkeeper_oauth_token = [pg_quote $token]" buf {
		set user_id $buf(id)
	}

	if {![info exists user_id]} {
		lassign [runkeeper_request user $token] success arrayinfo details
		array set ::rkuser $arrayinfo
		lassign [runkeeper_request profile $token] success arrayinfo details
		array set ::rkprofile $arrayinfo

		pg_select $::db "SELECT id FROM users WHERE id = [pg_quote $::rkuser(userID)]" buf {
			set sql "UPDATE users SET runkeeper_profile = [pg_quote [array get ::rkprofile]], runkeeper_userinfo = [pg_quote [array get ::rkuser]] WHERE id = $buf(id)"
			sql_exec $::db $sql
			set user_id $buf(id)
		}
	}

	if {![info exists user_id] && [info exists ::rkuser(userID)]} {
		unset -nocomplain ins
		set ins(runkeeper_oauth_token)	$token
		set ins(id)	$::rkuser(userID)
		set ins(runkeeper_profile)	[array get ::rkprofile]
		set ins(runkeeper_userinfo)	[array get ::rkuser]

		set user_id [sql_insert_from_array users ins id]
	}

	set sql "UPDATE sessions SET user_id = $user_id WHERE session = [pg_quote $::session(session)]"
	sql_exec $::db $sql
}

package provide ergkeeper 1.0


package provide ergkeeper 1.0
