# delimiter.tcl --
#
#       This file is a part of the XMPP library. It implements nested roster
#       groups server-side delimiter storing (XEP-0083).
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::private

package provide xmpp::roster::delimiter 0.1

namespace eval ::xmpp::roster::delimiter {
    namespace export store retrieve serialize deserialize
}

#
# Retrieving nested groups delimiter
#

proc ::xmpp::roster::delimiter::retrieve {xlib args} {
    set commands {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set id \
        [::xmpp::private::retrieve \
                    $xlib \
                    [list [::xmpp::xml::create roster \
                                               -xmlns roster:delimiter]] \
                    -command [namespace code [list ParseRetrieveResult \
                                                   $commands] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::delimiter::ParseRetireveResult {commands status xml} {
    if {[llength $commands] == 0} return

    if {![string equal $status ok]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }

    uplevel #0 [lindex $commands 0] [list ok [deserialize $xml]]
    return
}

proc ::xmpp::roster::delimiter::deserialize {xml} {
    foreach item $xml {
        ::xmpp::xml::split $item tag xmlns attrs cdata subels

        if {[string equal $xmlns roster:delimiter]} {
            return $cdata
        }
    }
}

#
# Storing nested groups delimiter
#

proc ::xmpp::roster::delimiter::serialize {delimiter} {
    return [::xmpp::xml::create roster \
                                -xmlns roster:delimiter \
                                -cdata $delimiter]
}

proc ::xmpp::roster::delimiter::store {xlib delimiter args} {
    set commands {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set id \
        [::xmpp::private::store \
                    $xlib \
                    [list [serialize $delimiter]] \
                    -command [namespace code [list ParseStoreResult $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::delimiter::ParseStoreResult {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
