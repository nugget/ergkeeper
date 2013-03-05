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
	append buf {<center><a id="rk_login-blue-black" class="rk_webButtonWithText200" href="}
	append buf "$::config(rkapi_auth_url)?"
	append buf [join $arglist "&"]
	append buf {" title="Login with RunKeeper, powered by the Health Graph"></a></center>}
}

proc runkeeper_content_type {method} {
	return "application/vnd.com.runkeeper.NewFitnessActivity+json"
}

proc runkeeper_request {method {token ""} {body ""}} {
	set success		0
	array set details {err "Unknown"}
	array set reponse {}

	if {$token == "" && [info exists ::user(runkeeper_oauth_token)] && $::user(runkeeper_oauth_token) != ""} {
		set token $::user(runkeeper_oauth_token)
	}

	if {$token == ""} {
		set details(err) "No token available"
		return [list $success [array get response] [array get details]]
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
	} else {
		::ergkeeper::log_error "runkeeper_request error:\ndetails: [array get details]\nresponse: [array get response]"
	}

	return [list $success [array get response] [array get details]]
}

proc runkeeper_bind_user {token} {

	pg_select $::db "SELECT * FROM users WHERE runkeeper_oauth_token = [pg_quote $token]" buf {
		set user_id $buf(id)
	}

	if {![info exists user_id]} {
		lassign [runkeeper_request user $token] success array_data details_data
		array set ::rkuser $array_data
		lassign [runkeeper_request profile $token] success array_data details_data
		array set ::rkprofile $array_data

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
	lassign [runkeeper_request $method "" $body] success array_data details_data
	#puts "<p>$success<br/>$array_data<br/>$details_data</p>"

	return [list $success $array_data $details_data]
}

proc runkeeper_post_activity {id} {
	set success 0
	array set details {}

	load_response

	pg_select $::db "SELECT * FROM activities WHERE id = $id" buf {
		if {![info exists response(resubmit)] && $buf(posted) != ""} {
			set details(err) "Duplicate (already posted)"
		} else {
			set yo [yajl create #auto]
			$yo map_open
			$yo string start_time string [clock format [clock scan $buf(start_time)] -format "%a, %d %b %Y %H:%M:%S"]
			$yo string equipment string "Row Machine"
			foreach f {type notes} {
				$yo string $f string $buf($f)
			}
			foreach f {total_distance duration average_heart_rate total_calories} {
				$yo string $f number $buf($f)
			}
			$yo string gymEquipment string "Rowing Machine"

			if {[info exists buf(splits)] && $buf(splits) ne ""} {

				$yo string distance array_open
				foreach split $buf(splits) {
					array set s $split
					if {[info exists s(timestamp)] && [info exists s(distance)] && $s(distance) ne ""} {
						$yo map_open string timestamp double $s(timestamp) string distance double $s(distance) map_close
					}
				}
				$yo array_close

				$yo string heart_rate array_open
				foreach split $buf(splits) {
					array set s $split
					if {[info exists s(timestamp)] && [info exists s(heart_rate)] && $s(heart_rate) ne ""} {
						$yo map_open string timestamp double $s(timestamp) string heart_rate double $s(heart_rate) map_close
					}
				}
				$yo array_close

			}

			$yo map_close
			set payload [$yo get]
			$yo delete

			if {[opt_bool debug]} {
				puts "<code>[$yo get]</code>"
				$yo delete
				return
			}
			lassign [runkeeper_json_post $::rkuser(fitness_activities) $payload] success array_data details_data

			unset -nocomplain details headers
			array set details $details_data
			array set headers $details(headers)
			unset -nocomplain details(headers)

			set error_text "json post error (activity_id $buf(id)):\n$payload\ndetails: [array get details]\nheaders: [array get headers]\nrequest: [array get request]"
			if {[string is true $success]} {
				if {[info exists headers(Location)]} {
					set sql "UPDATE activities SET runkeeper_uri = [pg_quote $headers(Location)] WHERE id = $id"
					sql_exec $::db $sql
				}
			} else {
				::ergkeeper::log_error $error_text
				puts "<p>RunKeeper Error</p>"
			}
		}
	}

	return [list $success [array get details]]
}

proc c2log_line_type {buf delimeter} {
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

	if {[regexp "^$delimeter" $buf]} {
		if {[lindex [split $buf $delimeter] 5] == ""} {
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

proc detect_date_format {log} {
	unset -nocomplain alist blist dlist

	foreach line [split $log "\n"] {
		if {[regexp {(\d+)[\.\/-](\d+)[\.\/-](\d+)} $line _ aa bb cccc]} {
			lappend alist [scan $aa %d]
			lappend blist [scan $bb %d]
			lappend dlist "$aa/$bb/$cccc"
		}
	}

	if {![info exists alist]} {
		return "unknown"
	}

	set alist [lsort -integer -unique -decreasing $alist]
	set blist [lsort -integer -unique -decreasing $blist]
	set dlist [lsort -unique $dlist]

	if {[lindex $alist 0] > 12 && [lindex $blist 0] <= 12} {
		return "ddmmyyyy"
	} elseif {[lindex $blist 0] > 12 && [lindex $alist 0] <= 12} {
		return "mmddyyyy"
	} else {
		return "unknown"
	}
}

proc detect_delimeter {log} {
	set delimeter ","

	foreach line [split $log "\n"] {
		if {[regexp {Log Data for:(.)} $line _ seen_delimeter]} {
			set delimeter $seen_delimeter
		}
	}

	return "$delimeter"
}

proc iso_date {buf format} {
	set retval $buf

	if {[regexp {(\d+)[\.\/-](\d+)[\.\/-](\d\d\d\d)} $buf _ aa bb cccc]} {
		switch $format {
			"mmddyyyy" {
				set retval "$cccc-$aa-$bb"
			}

			"ddmmyyyy" {
				set retval "$cccc-$bb-$aa"
			}
		}
	}
	if {[opt_bool debug]} {
		puts "<p>iso_date $buf $format = $retval"
	}
	return $retval
}

proc runkeeper_import_new_activities {user_id log} {
	set ::config(debug) 0

	unset -nocomplain activities username
	set version "unknown"

	set workouts_in_file 0
	set workouts_loaded  0

	set date_format [detect_date_format $log]
	set delimeter   [detect_delimeter $log]

	if {$date_format eq "unknown"} {
		puts "<p>Warning: unable to determine date format in log file</p>"
	}

	foreach line [split $log "\n"] {
		set type [c2log_line_type $line $delimeter]

		if {[opt_bool debug]} {
			incr linec
			puts "$linec - $type - $line"
		}
		switch $type {
			version {
				regexp {Version ([\d\.]+)} $line _ version
			}
			newuser {
				set username [lindex [split $line $delimeter] 1]
			}
			workout {
				unset -nocomplain ins activity_id field_list value_list
				set ins(version) $version

				# puts $line
				lassign [::csv::split $line $delimeter] _ name date time notes duration total_distance avg_spm heart_rate _ _ _ _ _ cal_hr

				set isodate     [iso_date $date $date_format]
				set start_epoch [clock scan "$isodate $time"]
				set start_time  [clock format $start_epoch -format "%Y-%m-%d %H:%M:%S"]

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

				set sql "INSERT INTO activities ([join $field_list ","]) SELECT [join $value_list ","] WHERE $where RETURNING id"
				if {[opt_bool debug]} {
					puts "<p><code>$sql</code></p>"
				}

				incr workouts_in_file

				set import_this_line 0
				if {![info exists ::user(logfile_username)] || $::user(logfile_username) == ""} {
					set import_this_line 1
				} else {
					if {$::user(logfile_username) == $name} {
						set import_this_line 1
					}
				}

				if {$import_this_line == 1} {
					pg_select $::db $sql buf {
						incr workouts_loaded
						unset -nocomplain splitlist incr_distance split_count
						set activity_id $buf(id)
					}
				}
			}

			split {
				# ,Nugget,2/5/13,20:32,0:30:07,,,,,05:00.0,1077,23,154,02:19.2,745,130
				lassign [::csv::split $line $delimeter] _ name date time notes _ _ _ _ split_time split_meters split_spm split_hr pace500 cal_hr avg_hr

				lassign [lreverse [split [lindex [split $split_time "."] 0] ":"]] ss mm hh
				set ss [scan $ss %d]
				set mm [scan $mm %d]
				set hh [scan $hh %d]

				set split_seconds 0
				if {$hh ne ""} {
					incr split_seconds [expr 60*60*$hh]
				}
				if {$ss eq "" || $mm eq ""} {
					#::ergkeeper::log_error "cannot parse split time:\n  $line\n  $split_time\n  $hh $mm $ss"
				} else {
					incr split_seconds [expr 60*$mm]
					incr split_seconds $ss

					#puts "<p>$line</p>"
					#puts "<p>secs $split_seconds time $split_time - meters $split_meters - spm $split_spm - hr $split_hr - pace/500m $pace500 - cal $cal_hr - hr $avg_hr</p>"
					incr incr_distance $split_meters
					lappend splitlist [list timestamp $split_seconds distance $incr_distance heart_rate $split_hr]
				}
			}

			empty {
				if {[info exists activity_id] && [info exists splitlist] && $splitlist ne ""} {
					set sql "UPDATE activities SET splits = [pg_quote $splitlist] WHERE id = $activity_id"
					sql_exec $::db $sql
					if {[opt_bool debug]} {
						puts "<p><code>$sql</code></p>"
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
