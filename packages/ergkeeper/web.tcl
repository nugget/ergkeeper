package require uuid

proc page_init {} {
	set ::db [dbconnect DB]
	unset -nocomplain ::session ::user

	array set ::session [get_session]

	load_config
}

proc page_term {} {
	dbdisconnect
	exit
}

proc page_head {} {
	puts "<html>"
	puts "<body>"
}

proc page_foot {} {
	if {1} {
		puts "<p>debug:</p>"
		foreach a {::session ::user} {
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

package provide ergkeeper 1.0

