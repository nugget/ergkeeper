package require http
package require tls
package require yajltcl

proc request_uri {state} {
	return $::config(rkapi_token_url)
}

proc get_oauth_token_from_code {code} {
	::http::register https 443 ::tls::socket

	set query [::http::formatQuery grant_type authorization_code code $code client_id $::config(rkapi_client_id) client_secret $::config(rkapi_client_secret) redirect_uri "$::config(base_url)login"]

	# puts "<code>[request_uri runkeeper]?$query</code>"

	set fp [::http::geturl [request_uri runkeeper] -query $query -timeout 15000 ]
	set status [::http::status $fp]
	set ncode [::http::ncode $fp]
	set err [::http::error $fp]
	set formdata [string trim [::http::data $fp]]
	::http::cleanup $fp

	# Extract the access token.
	if {$status != "ok" || $ncode != 200} {
		puts "Major Fail to retrieve access token: $status / $ncode / $formdata / $err"
	}

	set jsonkv [::yajl::json2dict $formdata]
	array set response $jsonkv
	if {[info exists response(access_token)]} {
		return $response(access_token)
	}

	puts "Failed to retrieve access token: $status / $ncode / $formdata / $err"
}

proc set_session_token {site token} {
	set field "${site}_oauth_token"

	pg_select $::db "SELECT * FROM users WHERE $field = [pg_quote $token]" buf {
		set user_id $buf(id)
	}

	if {![info exists user_id]} {
		set ins($field)	$token
		set user_id [sql_insert_from_array users ins id]
	}

	set sql "UPDATE sessions SET user_id = $user_id WHERE session = [pg_quote $::session(session)]"
	sql_exec $::db $sql
}

package provide ergkeeper 1.0
