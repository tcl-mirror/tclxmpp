# annotations.tcl --
#
#       This file is a part of the XMPP library. It implements storing
#       and retieving roster notes (XEP-0145).
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::private

package provide xmpp::roster::annotations 0.1

namespace eval ::xmpp::roster::annotations {
    namespace export store retrieve serialize deserialize
}

proc ::xmpp::roster::annotations::retrieve {xlib args} {
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
                                               -xmlns storage:rosternotes]] \
                    -command [namespace code [list ProcessRetrieveAnswer $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::annotations::ProcessRetrieveAnswer {commands status xml} {
    if {[llength $commands] == 0} return

    if {![string equal $status ok]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }

    uplevel #0 [lindex $commands 0] [list ok [deserialize $xml]]
    return
}

proc ::xmpp::roster::annotations::deserialize {xml} {
    set notes {}

    foreach xmldata $xml {
        ::xmpp::xml::split $xmldata tag xmlns attrs cdata subels

        if {[string equal $xmlns storage:rosternotes]} {
            foreach note $subels {
                ::xmpp::xml::split $note stag sxmlns sattrs scdata ssubels

                set jid   [::xmpp::xml::getAttr $sattrs jid]
                set cdate [::xmpp::xml::getAttr $sattrs cdate]
                set mdate [::xmpp::xml::getAttr $sattrs mdate]

                if {[catch { ScanTime $cdate } cdate]} {
                    set cdate [clock seconds]
                }
                if {[catch { ScanTime $mdate } mdate]} {
                    set mdate [clock seconds]
                }

                lappend notes [list jid $jid cdate $cdate mdate $mdate note $scdata]
            }
        }
    }

    return $notes
}

proc ::xmpp::roster::annotations::ScanTime {timestamp} {
    if {[regexp {(.*)T(.*)Z} $timestamp -> date time]} {
        return [clock scan "$date $time" -gmt true]
    } else {
        return [clock scan $timestamp -gmt true]
    }
}

proc ::xmpp::roster::annotations::serialize {notes} {
    set tags {}
    foreach note $notes {
        array unset n
        array set n $note
        if {[string equal $n(note) ""]} continue

        set vars [list jid $n(jid)]

        if {![catch {clock format $n(cdate) \
                                  -format "%Y-%m-%dT%TZ" -gmt true} cdate]} {
            lappend vars cdate $cdate
        }

        if {![catch {clock format $n(mdate) \
                                  -format "%Y-%m-%dT%TZ" -gmt true} mdate]} {
            lappend vars mdate $mdate
        }

        lappend tags [::xmpp::xml::create note \
                                          -attrs $vars \
                                          -cdata $n(note)]
    }

    return [::xmpp::xml::create storage \
                                -xmlns storage:rosternotes \
                                -subelements $tags]
}

proc ::xmpp::roster::annotations::store {xlib notes args} {
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
                    [list [serialize $notes]] \
                    -command [namespace code [list ProcessStoreAnswer $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::annotations::ProcessStoreAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
