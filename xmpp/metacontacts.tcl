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

namespace eval ::xmpp::roster::metacontacts {
    namespace export store retrieve serialize deserialize
}

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
                       [::msgcat::mc "Illegal option \"%s\"" $key]
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

    uplevel #0 [lindex $commands 0] [list ok [deserialize $xml]]
    return
}

proc ::xmpp::roster::metacontacts::deserialize {xml} {
    foreach xmldata $xml {
        ::xmpp::xml::split $xmldata tag xmlns attrs cdata subels

        if {[string equal $xmlns storage:metacontacts]} {
            foreach meta $subels {
                ::xmpp::xml::split $meta stag sxmlns sattrs scdata ssubels

                set jid   [::xmpp::xml::getAttr $sattrs jid]
                set tag   [::xmpp::xml::getAttr $sattrs tag]
                set order [::xmpp::xml::getAttr $sattrs order]
                if {![string is integer -strict $order]} {
                    set order 0
                }

                lappend contacts($tag) [list $jid $order]
            }
        }
    }

    foreach tag [array names contacts] {
        foreach jo [lsort -integer -index 1 $contacts($tag)] {
            lappend result($tag) [lindex $jo 0]
        }
    }

    return [array get result]
}

proc ::xmpp::roster::metacontacts::serialize {contacts} {
    set tags {}
    foreach {tag jids} $contacts {
        set order 1
        foreach jid $jids {
            set attrs [list jid $jid tag $tag order $order]

            lappend tags [::xmpp::xml::create meta -attrs $attrs]
            incr order
        }
    }

    return [::xmpp::xml::create storage \
                                -xmlns storage:metacontacts \
                                -subelements $tags]
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
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set id \
        [::xmpp::private::store \
                    $xlib \
                    [list [serialize $contacts]] \
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
