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

proc runkeeper_content_type {method} {
	return "application/vnd.com.runkeeper.NewFitnessActivity+json"
}

proc runkeeper_request {method {token ""} {body ""}} {
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

	::http::config -useragent "ErgKeeper/1.0"
	::http::register https 443 ::tls::socket

	if {$body != ""} {
    	set fp [::http::geturl $uri -timeout 15000 -headers $headers -query $body -type [runkeeper_content_type $method]]
	} else {
    	set fp [::http::geturl $uri -timeout 15000 -headers $headers]
	}
	set status [::http::status $fp]
	set ncode [::http::ncode $fp]
	set err [::http::error $fp]
	array set retheaders [::http::meta $fp]
	set formdata [string trim [::http::data $fp]]
	upvar #0 $fp state
	# parray state
	::http::cleanup $fp

	set details "uri:($uri) status:($status) ncode:($ncode) data:($formdata) err:($err) headers:([array get retheaders])"

    set jsonkv [::yajl::json2dict $formdata]

	# puts "<pre>$jsonkv</pre>"
    array set response $jsonkv

	# parray response

	if {$ncode >= 200 && $ncode <= 399} {
		set success 1
	}

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

proc runkeeper_json_post {method body} {
	puts "<h1>JSON Post</h1><pre>$body</pre>"
	lassign [runkeeper_request $method "" $body] success array_data details
	puts "<p>$success<br/>$array_data<br/>$details</p>"
}

proc runkeeper_post_activity {id} {
	set success 0
	set details ""

	pg_select $::db "SELECT * FROM activities WHERE id = $id" buf {
		if {$buf(posted) != ""} {
			set details "Duplicate (already posted)"
		} else {
			set yo [yajl create #auto]
			$yo map_open
			$yo string start_time string [clock format [clock scan $buf(start_time)] -format "%a, %d %b %Y %H:%M:%S"]
			foreach f {type notes} {
				$yo string $f string $buf($f)
			}
			foreach f {total_distance duration average_heart_rate total_calories} {
				$yo string $f number $buf($f)
			}
			$yo string gymEquipment string "Rowing Machine"
			$yo map_close
			runkeeper_json_post fitnessActivities [$yo get]
			$yo delete
		}
	}

	return [list $success $details]
}

package provide ergkeeper 1.0
