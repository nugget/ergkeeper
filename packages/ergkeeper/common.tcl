proc opt_bool {item} {
	set retval 0

	if {[info exists ::config($item)]} {
		set retval [string is true $::config($item)]
	}

	return $retval
}


package provide ergkeeper 1.0
