# plkIndex.tcl --
#
#       Tcl package index file for TclXML
#
# $Id$

package ifneeded xml 2.0 {
    package require -exact xml::tcl 2.0
    package require -exact xmldefs 2.0
    package require -exact xml::tclparser 2.0

    package provide xml 2.0
}

package ifneeded xml::tcl 2.0       [list source [file join $dir xmltcl.tcl]]
package ifneeded sgmlparser 1.0     [list source [file join $dir sgmlparser.tcl]]
package ifneeded sgml 1.8           [list source [file join $dir sgml.tcl]]
package ifneeded xmldefs 2.0        [list source [file join $dir xml.tcl]]
package ifneeded xml::tclparser 2.0 [list source [file join $dir tclparser.tcl]]

# vim:ft=tcl:ts=8:sw=4:sts=4:et
