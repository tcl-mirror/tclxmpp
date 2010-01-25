# private.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       Private XML Storage (XEP-0049).
#
# Copyright (c) 2009-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::private 0.1

namespace eval ::xmpp::private {}

proc ::xmpp::private::store {xlib query args} {
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
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set id \
        [::xmpp::sendIQ $xlib set \
                   -query [::xmpp::xml::create query \
                                               -xmlns jabber:iq:private \
                                               -subelements $query] \
                   -command [namespace code [list ParseStoreAnswer $commands]] \
                   -timeout $timeout]
    return $id
}

proc ::xmpp::private::ParseStoreAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

proc ::xmpp::private::retrieve {xlib query args} {
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
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set id \
        [::xmpp::sendIQ $xlib get \
                   -query [::xmpp::xml::create query \
                                               -xmlns jabber:iq:private \
                                               -subelements $query] \
                   -command [namespace code [list ParseRetrieveAnswer $commands]] \
                   -timeout $timeout]
    return $id
}

proc ::xmpp::private::ParseRetrieveAnswer {commands status xml} {
    if {[llength $commands] == 0} return

    if {![string equal $status ok]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    uplevel #0 [lindex $commands 0] [list ok $subels]
    return
}

# vim:ts=8:sw=4:sts=4:et
