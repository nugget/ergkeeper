package require Rivet

proc opt_bool {item} {
	set retval 0

	if {[info exists ::config($item)]} {
		set retval [string is true $::config($item)]
	}

	return $retval
}

namespace eval ::ergkeeper {
	proc require_admin {} {
		if {![info exists ::user(admin)] || [string is false -strict $::user(admin)]} {
			puts "<p>Access Denied</p>"
			::ergkeeper::page_foot
			::ergkeeper::page_term
		}
	}
}

package provide ergkeeper 1.0
