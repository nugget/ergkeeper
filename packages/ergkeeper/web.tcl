package require uuid
package require form

proc page_init {} {
	set ::db [dbconnect DB]
	unset -nocomplain ::session ::user

	load_config
	array set ::session [get_session]
}

proc page_term {} {
	dbdisconnect
	exit
}

proc page_head {} {
	puts "<html>"
	puts "<body>"

	if {[info exists ::session(user_id)] && $::session(user_id) != ""} {
		if {[info exists ::rkuser(medium_picture)]} {
			puts "<img src=\"$::rkuser(medium_picture)\">"
		}
		puts "<p>Logout</p>"
	}

}

proc page_foot {} {
	if {1} {
		puts "<p>debug:</p>"
		foreach a {::session ::user ::rkuser} {
			if {[info exists $a]} {
				parray $a
			}
		}
	}
	puts "</body>"
	puts "</html>"
}

proc page_response {} {
	uplevel 1 {
		unset -nocomplain response
		load_response

		if {![array exists response]} {
			array set response {}
		}
	}
}

proc load_user {id} {
	array set ::user {}

	if {[info exists id] && $id != "" && [ctype digit $id]} {
		pg_select $::db "SELECT * FROM users WHERE id = $id" buf {
			array set ::user [array get buf {[a-z]*}]

			if {[info exists ::user(runkeeper_oauth_token)]} {
		        lassign [runkeeper_request user] success arrayinfo details
		        array set ::rkuser $arrayinfo
		        lassign [runkeeper_request profile] success arrayinfo details
		        array set ::rkprofile $arrayinfo
			}
		}
	}
}

proc get_session {} {
	set session [cookie get ergkeeper_session]

	if {$session != ""} {
		pg_select $::db "SELECT * FROM sessions WHERE session = [pg_quote $session]" buf {
			array set ::session [array get buf {[a-z]*}]
			load_user $buf(user_id)
			update_session $session
			return [array get ::session]
		}
	}

	if {![info exists ::session]} {
		set ins(session)		[::uuid::uuid generate]
		set ins(source)			[env SERVER_NAME]
		set ins(referer)		[env HTTP_REFERER]
		set ins(ip_create)		[env REMOTE_ADDR]
		set ins(ip_recent)		$ins(ip_create)
		set ins(agent_create)	[env HTTP_USER_AGENT]
		set ins(agent_recent)	$ins(agent_create)

		if {[sql_insert_from_array sessions ins]} {
			cookie set ergkeeper_session $ins(session) -path "/" -days 3650
		}

		unset -nocomplain ::session
		pg_select $::db "SELECT * FROM sessions WHERE session = [pg_quote $ins(session)]" buf {
			return [array get buf {[a-z]*}]
		}
	}

	return {session ""}
}

proc update_session {id} {
	set sql "UPDATE sessions SET ip_recent = [pg_quote [env REMOTE_ADDR]], agent_recent = [pg_quote [env HTTP_USER_AGENT]] WHERE session = [pg_quote $id]"
	sql_exec $::db $sql
}

proc require_login {} {
	if {![info exists ::user(id)]} {
		puts [runkeeper_login_button]
		page_foot
		page_term
	}
}

proc table {command {id "default"}} {
	switch $command {
		start {
			upvar row_$id row
			if {[info exists row]} {
				unset row
			}
			return "<table>"
		}
		end {
			upvar row_$id row
			if {[info exists row]} {
				unset row
			}
			return "</table>"
		}
		default {
			return "<!-- unknown table command $command -->"
		}
	}
}

proc rowclass {prefix {id "default"}} {
	upvar row_$id row

	if {![info exists row] || $row != 1} {
		set row 1
	} else {
		set row 2
	}
	return "class=\"$prefix$row\""
}

proc head {buf} {
	return "<h2>$buf</h2>"
}

package provide ergkeeper 1.0

