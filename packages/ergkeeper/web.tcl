package provide ergkeeper 1.0

proc page_init {} {
	set ::db [dbconnect DB]
	unset -nocomplain ::session
}

proc page_term {} {
	dbdisconnect
}
