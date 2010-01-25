# bookmarks.tcl --
#
#       This file is a part of the XMPP library. It implements storing
#       and retieving conference bookmarks (XEP-0048).
#
# Copyright (c) 2009-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::private

package provide xmpp::roster::bookmarks 0.1

namespace eval ::xmpp::roster::bookmarks {
    namespace export store retrieve serialize deserialize
}

proc ::xmpp::roster::bookmarks::retrieve {xlib args} {
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
                                               -xmlns storage:bookmarks]] \
                    -command [namespace code [list ProcessRetrieveAnswer $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::bookmarks::ProcessRetrieveAnswer {commands status xml} {
    if {[llength $commands] == 0} return

    if {![string equal $status ok]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }

    uplevel #0 [lindex $commands 0] [list ok [deserialize $xml]]
    return
}

proc ::xmpp::roster::bookmarks::deserialize {xml} {
    set bookmarks {}

    foreach xmldata $xml {
        ::xmpp::xml::split $xmldata tag xmlns attrs cdata subels

        if {[string equal $xmlns storage:bookmarks]} {
            foreach bookmark $subels {
                ::xmpp::xml::split $bookmark stag sxmlns sattrs scdata ssubels

                set res [list jid [::xmpp::xml::getAttr $sattrs jid]]

                if {[::xmpp::xml::isAttr $sattrs autojoin]} {
                    set autojoin [::xmpp::xml::getAttr $sattrs autojoin]
                    if {[string is boolean -strict $autojoin]} {
                        lappend res autojoin [::xmpp::xml::getAttr $sattrs autojoin]
                    }
                }

                if {[::xmpp::xml::isAttr $sattrs name]} {
                    lappend res name [::xmpp::xml::getAttr $sattrs name]
                }

                foreach subel $ssubels {
                    ::xmpp::xml::split $subel sstag ssxmlns ssattrs sscdata sssubels

                    switch -- $sstag {
                        nick {
                            lappend res nick $sscdata
                        }
                        password {
                            lappend res password $sscdata
                        }
                    }
                }

                lappend bookmarks $res
            }
        }
    }

    return $bookmarks
}

proc ::xmpp::roster::bookmarks::serialize {bookmarks} {
    set tags {}
    foreach bookmark $bookmarks {
        array unset n
        array set n $bookmark

        set vars [list jid $n(jid)]

        if {[info exists n(name)]} {
            lappend vars name $n(name)
        }

        if {[info exists n(autojoin)]} {
            lappend vars autojoin $n(autojoin)
        }

        set subels {}

        if {[info exists n(nick)]} {
            lappend subels [::xmpp::xml::create nick -cdata $n(nick)]
        }

        if {[info exists n(password)]} {
            lappend subels [::xmpp::xml::create password -cdata $n(password)]
        }

        lappend tags [::xmpp::xml::create conference \
                                          -attrs $vars \
                                          -subelements $subels]
    }

    return [::xmpp::xml::create storage \
                                -xmlns storage:bookmarks \
                                -subelements $tags]
}

proc ::xmpp::roster::bookmarks::store {xlib bookmarks args} {
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
                    [list [serialize $bookmarks]] \
                    -command [namespace code [list ProcessStoreAnswer $commands]] \
                    -timeout $timeout]
    return $id
}

proc ::xmpp::roster::bookmarks::ProcessStoreAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
