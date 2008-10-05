# Tcl package index file - handcrafted
#
# $Id$

package ifneeded xml 2.0 {
    package require -exact xml::tcl 2.0
    package require -exact xmldefs 2.0
    package require -exact xml::tclparser 2.0
    package provide xml 2.0
}

package ifneeded xml::tcl 2.0 [list source [file join $dir xml__tcl.tcl]]
package ifneeded sgmlparser 1.0 [list source [file join $dir sgmlparser.tcl]]

package ifneeded sgml 1.8 [list source [file join $dir sgml-8.1.tcl]]
package ifneeded xmldefs 2.0 [list source [file join $dir xml-8.1.tcl]]
package ifneeded xml::tclparser 2.0 [list source [file join $dir tclparser-8.1.tcl]]

