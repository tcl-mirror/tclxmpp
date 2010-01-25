# roster.tcl --
#
#       This file is a part of the XMPP library. It implements basic
#       roster routines (RFC-3291).
#
# Copyright (c) 2008-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::roster 0.1

namespace eval ::xmpp::roster {}

# ::xmpp::roster::new --

proc ::xmpp::roster::new {xlib args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    set state(xlib) $xlib
    set state(rid) 0
    set state(items) {}

    foreach {key val} $args {
        switch -- $key {
            -itemcommand {
                set state($key) $val
            }
            default {
                unset state
                return -code error \
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::iq::RegisterIQ $xlib set * jabber:iq:roster \
                           [namespace code [list ParsePush $token]]
    return $token
}

# ::xmpp::roster::free --

proc ::xmpp::roster::free {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::iq::UnregisterIQ $xlib set * jabber:iq:roster

    unset state
    return
}

# ::xmpp::roster::items --

proc ::xmpp::roster::items {token args} {
    variable $token
    upvar 0 $token state

    set normalized false

    foreach {key val} $args {
        switch -- $key {
            -normalized {
                set normalized $val
            }
        }
    }

    if {$normalized} {
        return $state(items)
    } else {
        set items {}
        foreach njid $state(items) {
            lappend items [::xmpp::xml::getAttr $state(roster,$njid) jid]
        }
        return $items
    }
}

# ::xmpp::roster::item --

proc ::xmpp::roster::item {token jid {key -all}} {
    variable $token
    upvar 0 $token state

    set njid [::xmpp::jid::normalize $jid]

    switch -- $key {
        -all {
            if {![info exists state(roster,$njid)]} {
                return {}
            } else {
                return $state(roster,$njid)
            }
        }
        -jid -
        -name -
        -subscription -
        -ask -
        -groups {
            if {![info exists state(roster,$njid)]} {
                return ""
            } else {
                return [::xmpp::xml::getAttr $state(roster,$njid) $key]
            }
        }
        default {
            return -code error \
                   [::msgcat::mc "Illegal option \"%s\"" $key]
        }
    }
}

# ::xmpp::roster::remove --

proc ::xmpp::roster::remove {token jid args} {
    eval [list send $token -jid $jid -subscription remove] $args
}

# ::xmpp::roster::send --

proc ::xmpp::roster::send {token args} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    set timeout 0
    set cmd {}
    set item {}
    set subels {}

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set cmd [list -command $val]
            }
            -jid {
                if {[llength $item] > 0} {
                    lappend subels [eval $item]
                }
                set item [list ::xmpp::xml::create item -attrs [list jid $val]]
            }
            -name {
                lappend item -attrs [list name $val]
            }
            -subscription {
                lappend item -attrs [list subscription $val]
            }
            -ask {
                lappend item -attrs [list ask $val]
            }
            -groups {
                set groups {}
                foreach group $val {
                    lappend groups [::xmpp::xml::create group -cdata $group]
                }
                lappend item -subelements $groups
            }
            default {
                return -code error \
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set query [::xmpp::xml::create query -xmlns jabber:iq:roster \
                                         -subelements $subels]

    eval [list ::xmpp::sendIQ $xlib set \
                              -query $query \
                              -timeout $timeout] $cmd
}

# ::xmpp::roster::get --

proc ::xmpp::roster::get {token args} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    set timeout 0
    set cmd {}

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set cmd [list $val]
            }
            default {
                return -code error \
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set rid [incr state(rid)]

    ::xmpp::sendIQ $xlib get \
                   -query [::xmpp::xml::create query \
                                               -xmlns jabber:iq:roster] \
                   -command [namespace code [list ParseAnswer $token \
                                                              $rid \
                                                              $cmd]] \
                   -timeout $timeout

    if {[llength $cmd] > 0} {
        # Asynchronous mode
        return $token
    } else {
        # Synchronous mode
        vwait $token\(status,$rid)

        foreach {status msg} $state(status,$rid) break
        unset state(status,$rid)

        if {[string equal $status ok]} {
            return $msg
        } else {
            if {[string equal $status abort]} {
                return -code break $msg
            } else {
                return -code error $msg
            }
        }
    }
}

# ::xmpp::roster::ParsePush --

proc ::xmpp::roster::ParsePush {token xlib from xmlElement args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    # -to attribute contains the own JID, so check from JID to prevent
    # malicious users to pretend they perform roster push
    set to [::xmpp::xml::getAttr $args -to]

    if {![string equal $from ""] && \
            ![::xmpp::jid::equal $from $to] && \
            ![::xmpp::jid::equal $from [::xmpp::jid::stripResource $to]] && \
            ![::xmpp::jid::equal $from [::xmpp::jid::server $to]]} {

        return [list error cancel service-unavailable]
    }

    ParseItems $token $xmlElement

    return [list result [::xmpp::xml::create query -xmlns jabber:iq:roster]]
}

# ::xmpp::roster::ParseAnswer --

proc ::xmpp::roster::ParseAnswer {token rid cmd status xmlElement} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $rid '$cmd' $status"

    if {[string equal $status ok]} {
        ParseItems $token $xmlElement
        set xmlElement ""
    }

    if {[llength $cmd] > 0} {
        uplevel #0 [lindex $cmd 0] [list $status $xmlElement]
    } else {
        # Trigger vwait in [roster]
        set state(status,$rid) [list $status $xmlElement]
    }
    return
}

# ::xmpp::roster::ParseItems --

proc ::xmpp::roster::ParseItems {token xmlElement} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        set groups {}
        set jid    [::xmpp::xml::getAttr $sattrs jid]
        set name   [::xmpp::xml::getAttr $sattrs name]
        set subsc  [::xmpp::xml::getAttr $sattrs subscription]
        set ask    [::xmpp::xml::getAttr $sattrs ask]

        foreach ssubel $ssubels {
            ::xmpp::xml::split $ssubel sstag ssxmlns ssattrs sscdata sssubels

            switch -- $sstag {
                group {
                    lappend groups $sscdata
                }
            }
        }

        set njid [::xmpp::jid::normalize $jid]

        switch -- $subsc {
            remove {
                # Removing roster item

                set idx [lsearch -exact $state(items) $njid]
                if {$idx >= 0} {
                    set state(items) [lreplace $state(items) $idx $idx]
                }

                catch {unset state(roster,$njid)}
            }
            default {
                # Updating or adding roster item

                set state(items) \
                    [lsort -unique [linsert $state(items) 0 $njid]]

                set state(roster,$njid) [list jid          $jid \
                                              name         $name \
                                              subscription $subsc \
                                              ask          $ask \
                                              groups       $groups]
            }
        }

        if {[info exists state(-itemcommand)]} {
            uplevel #0 $state(-itemcommand) [list $njid \
                                                  -jid          $jid \
                                                  -name         $name \
                                                  -subscription $subsc \
                                                  -ask          $ask \
                                                  -groups       $groups]
        }
    }

    return
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
