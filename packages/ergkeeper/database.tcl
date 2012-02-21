package require Tclx
package require Pgtcl

proc dbconnect {DB} {
	if {[catch {set db [pg_connect -connlist [array get ::$DB]]} result] == 1} {
		puts "Unable to connect to database: $result"

	} else {
		return $db
	}
}

proc dbdisconnect {} {
	global db
	if {[info exists db]} {
		catch {pg_disconnect $db}
	}
}

proc sql_exec {conn sql} {
    set result [pg_exec $conn $sql]
    set status [pg_result $result -status]
	set start  [clock microseconds]

    if {[string match "PGRES_*_OK" $status]} {
        set success 1
    } else {
        # errordisplay_add "$status running code:<div class=\"debug_code\">$sql</div>Returned:<div class=\"debug_code\">[pg_result $result -error]</div>"
		puts "<code>SQL ERROR:<br />$status<br />$sql<br />[pg_result $result -error]</code>"
        set success 0
    }

	pg_result $result -clear

	set duration [expr [clock microseconds] - $start]

	# puts "<!-- $sql duration $duration -->"
	return $success
}

package provide ergkeeper 1.0
