# metacontacts.tcl --
#
#       This file is a part of the XMPP library. It implements storing and
#       retieving metacontacts information (XEP-0209).
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::private

package provide xmpp::roster::metacontacts 0.1

namespace eval ::xmpp::roster::metacontacts {}

proc ::xmpp::roster::metacontacts::retrieve {xlib args} {
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
                    [list [::xmpp::xml::create storage \
                                               -xmlns storage:metacontacts]] \
                    -command [namespace code [list ProcessRetrieveAnswer $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::metacontacts::ProcessRetrieveAnswer {commands status xml} {
    if {[llength $commands] == 0} return

    if {![string equal $status ok]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }

    set contacts {}

    foreach xmldata $xml {
        ::xmpp::xml::split $xmldata tag xmlns attrs cdata subels

        if {[string equal $xmlns storage:metacontacts]} {
            foreach meta $subels {
                ::xmpp::xml::split $meta stag sxmlns sattrs scdata ssubels

                set jid   [::xmpp::xml::getAttr $sattrs jid]
                set tag   [::xmpp::xml::getAttr $sattrs tag]
                set order [::xmpp::xml::getAttr $sattrs order]

                lappend contacts [list jid $jid tag $tag order $order]
            }
        }
    }

    uplevel #0 [lindex $commands 0] [list ok $contacts]
    return
}

proc ::xmpp::roster::metacontacts::store {xlib contacts args} {
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

    set tags {}
    foreach meta $contacts {
        array unset n
        array set n $meta

        set attrs [list jid $n(jid) tag $n(tag) order $n(order)]

        lappend tags [::xmpp::xml::create meta \
                                          -attrs $vars]
    }

    set id \
        [::xmpp::private::retrieve \
                    $xlib \
                    [list [::xmpp::xml::create storage \
                                        -xmlns storage:metacontacts \
                                        -subelements $tags]] \
                    -command [namespace code [list ProcessStoreAnswer $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::metacontacts::ProcessStoreAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
