package require uuid
package require form

namespace eval ::ergkeeper {
	proc page_init {} {
		set ::db [dbconnect ergDB]
		unset -nocomplain ::session ::user

		load_config
		array set ::session [get_session]
	}

	proc page_term {} {
		dbdisconnect
		abort_page
	}

	proc page_head {{title "ErgKeeper"}} {
		puts "<html>"
		puts "<head>"
		puts "<title>$title</title>"
		puts {<link rel="stylesheet" href="/css/default.css" type="text/css" />}
		puts {<link rel="shortcut icon" href="/favicon.ico" />}
		puts "</head>"
		puts "<body>"

		puts "<div class=\"header\">"
		puts "<a href=\"/\"><img class=\"topimage\" border=\"0\" src=\"/images/logo-xparent.png\" /></a>"

		set menu {/about "About ErgKeeper" /upload "Upload" /chooser "Post" /privacy "Privacy"}

		if {[info exists ::user(admin)] && [string is true -strict $::user(admin)]} {
			set menu [concat $menu {/admin/ Admin}]
		}

		if {[info exists ::user(id)]} {
			if {[info exists ::rkprofile(small_picture)]} {
				set img_url $::rkprofile(small_picture)
			} else {
				set img_url "/images/userpic.jpg"
			}
			lappend menu "/logout"
			lappend menu "Logout <span style=\"font-weight: normal;\">(<img class=\"topuser\" height=\"20\" width=\"20\" src=\"$img_url\" /> $::rkprofile(name))</span>"

			#puts "<a href=\"/logout\" class=\"topuser\">Logout <span style=\"font-weight: normal;\">(<img class=\"topuser\" height=\"20\" width=\"20\" src=\"$img_url\" /> $::rkprofile(name))</span></a>"
		}

		foreach {uri label} $menu {
			puts "<a href=\"$uri\" class=\"topmenu\">$label</a> "
		}


		puts "</div>"
		puts "<div class=\"body\">"
	}

	proc page_foot {} {
		puts "</div>"

		if {0} {
			puts "<p>debug:</p>"
			foreach a {::session ::user ::rkuser ::rkprofile} {
				if {[info exists $a]} {
					parray $a
				}
			}
		}

		# puts "<div class=\"footer\">&copy; Copyright 2012 David C. McNett.  All Rights Reserved.</div>"
		puts "</body>"
		puts "</html>"
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

	proc page_response {} {
		uplevel 1 {
			unset -nocomplain response
			load_response

			if {![array exists response]} {
				array set response {}
			}
		}
	}

	proc site_error {{extra_message ""}} {
		catch {log_error}
		headers numeric 500

		if {[opt_bool show_tracebacks] && [info exists ::errorInfo]} {
			puts "<h1>Rivet Error</h1>"
			puts "<pre class=\"traceback\">$::errorInfo</pre>"
		}

		puts "<p>I'm sorry, but an error has occurred.</p>"
		puts "<p>$extra_message</p>"
		puts "<p>Help can be reached at support@ergkeeper.com or you can open an issue on the"
		puts "<a href=\"https://github.com/nugget/ergkeeper/issues\">issue tracker</a>.</p>"

		return
	}

	proc log_error {} {
		unset -nocomplain field_list data_list

		set ins(vhost)			[apache_info virtual]
		set ins(ip)				[env REMOTE_ADDR]
		set ins(url)			[env REQUEST_URI]
		set ins(referer)		[env HTTP_REFERER]
		set ins(user_agent)		[env HTTP_USER_AGENT]
		if {[info exists ::user(id)]} {
			set ins(user_id) $::user(id)
		}

		if {[info exists ::errorInfo]} {
			set ins(error)		$::errorInfo
		} else {
			set ins(error)		"UNKNOWN"
		}

		sql_insert_from_array site_errors ins
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

proc head {buf {level 2}} {
	return "<h$level>$buf</h$level>"
}

proc apache_info {type} {
    switch $type {
        alias {
            set host [env HTTP_HOST]
            if {$host == ""} {
                set host ergkeeper.com
            }
            return $host
        }
        virtual { return [env SERVER_NAME] }
        real { return [info host] }
        ssl { return [env SERVER_NAME] }
    }
}

package provide ergkeeper 1.0

