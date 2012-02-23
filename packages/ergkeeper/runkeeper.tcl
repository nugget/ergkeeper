package require http
package require tls
package require csv

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

	unset -nocomplain details
	set details(uri)		$uri
	set details(status)		$status
	set details(ncode)		$ncode
	set details(data)		$formdata
	set details(err)		$err
	set details(headers)	[array get retheaders]

    set jsonkv [::yajl::json2dict $formdata]

	# puts "<pre>$jsonkv</pre>"
    array set response $jsonkv

	# parray response

	if {$ncode >= 200 && $ncode <= 399} {
		set success 1
	}

	return [list $success [array get response] [array get details]]
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
	set ::session(user_id) $user_id
}

proc runkeeper_json_post {method body} {
	#puts "<h1>JSON Post</h1><pre>$body</pre>"
	lassign [runkeeper_request $method "" $body] success array_data details
	#puts "<p>$success<br/>$array_data<br/>$details</p>"

	return [list $success $array_data $details]
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
			lassign [runkeeper_json_post $::rkuser(fitness_activities) [$yo get]] success array_data details_data

			unset -nocomplain details headers
			array set details $details_data
			array set headers $details(headers)

			if {[string is true $success]} {
				if {[info exists headers(Location)]} {
					set sql "UPDATE activities SET runkeeper_uri = [pg_quote $headers(Location)] WHERE id = $id"
					sql_exec $::db $sql
				}
			} else {
				puts "<p>RunKeeper Error:</p><pre>[$yo get]</pre>"
				parray details
				parray headers
			}

			$yo delete
		}
	}

	return [list $success $details_data]
}

proc c2log_line_type {buf} {
	set buf [string trim $buf]

	if {$buf == ""} {
		return "empty"
	}

	if {[regexp {Log Data for:} $buf]} {
		return "newuser"
	}

	if {[regexp {Version (.+)} $buf]} {
		return "version"
	}
	if {[regexp {(Concept2 Utility|Time of Day|Total Workout Results)} $buf]} {
		return "header"
	}

	if {[regexp {^,} $buf]} {
		if {[lindex [split $buf ","] 5] == ""} {
			return "split"
		} else {
			return "workout"
		}
	}

}

proc c2log_duration_to_interval {duration} {

	set colon_count [string length [regsub -all {[^:]} $duration ""]]
	if {$colon_count == 2} {
		set duration [lindex [split $duration "."] 0]
	}

	return $duration
}


proc pg_integer {buf} {
	set buf [lindex [split $buf "."] 0]
	if {[string is integer $buf]} {
		return $buf
	} else {
		return "NULL"
	}
}

proc runkeeper_import_new_activities {user_id log} {
	unset -nocomplain activities username
	set version "unknown"

	set workouts_in_file 0
	set workouts_loaded  0

	foreach line [split $log "\n"] {
		set type [c2log_line_type $line]

		switch $type {
			version {
				regexp {Version (.+)} $line _ version
			}
			newuser {
				set username [lindex [split $line ","] 1]
			}
			empty - header { }

			workout {
				unset -nocomplain ins
				set ins(version) $version

				# puts $line
				lassign [::csv::split $line] _ name date time notes duration total_distance avg_spm heart_rate _ _ _ _ _ cal_hr

				set start_time [clock format [clock scan "$date $time"] -format "%Y-%m-%d %H:%M:%S"]

				set notes_regexp [lindex [split $notes "."] 0]
				set notes_regexp [regsub {^0:} $notes_regexp ""]

				if {[regexp $notes_regexp $duration] && ![regexp {0:00} $duration]} {
					set notes "'Just Row' Workout"
				} else {
					set notes "$notes Workout"
				}

				set duration [c2log_duration_to_interval $duration]

				set where "1 NOT IN (SELECT 1 FROM activities WHERE deleted IS NULL AND user_id = $user_id AND start_time = [pg_quote $start_time] LIMIT 1)"

				set field_list {user_id start_time total_distance duration average_heart_rate total_calories name notes raw version}

				set value_list [list]
				lappend value_list [pg_integer $user_id]
				lappend value_list [pg_quote $start_time]
				lappend value_list [pg_integer $total_distance]
				lappend value_list "extract(epoch from [pg_quote $duration]::interval)::integer"
				lappend value_list [pg_integer $heart_rate]
				lappend value_list "(((extract(epoch from [pg_quote $duration]::interval)::float)/3600)*[pg_integer $cal_hr])::integer"
				lappend value_list [pg_quote $name]
				lappend value_list [pg_quote $notes]
				lappend value_list [pg_quote $line]
				lappend value_list [pg_quote $version]

				set sql "INSERT INTO activities ([join $field_list ","]) SELECT [join $value_list ","] WHERE $where RETURNING 1"

				if {[info exists ::user(logfile_username)] && $::user(logfile_username) != ""} {
					if {$::user(logfile_username) == $name} {

						incr workouts_in_file

						pg_select $::db $sql buf {
							# puts "<code>$sql</code><br/>"
							incr workouts_loaded
						}
					}
				}
			}

			default { }
		}
	}

	puts "<p>Loaded $workouts_loaded workouts from file of $workouts_in_file</p>"
	return [list $workouts_loaded $workouts_in_file]
}

package provide ergkeeper 1.0
