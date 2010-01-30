# muc.tcl --
#
#       This file is a part of the XMPP library. It implements Multi
#       User Chat (XEP-0045).
#
# Copyright (c) 2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::muc 0.1

namespace eval ::xmpp::muc {}

# ::xmpp::muc::new --

proc ::xmpp::muc::new {xlib room args} {
    variable id

    if {![string equal [::xmpp::jid::resource $room] ""]} {
        return -code error \
               [::msgcat::mc "MUC room JID must have empty resource part.\
                              The specified JID was \"%s\"" $room]
    }

    if {[catch {set room [::xmpp::jid::normalize $room]}]} {
        return -code error \
               [::msgcat::mc "MUC room JID \"%s\" is malformed" $room]
    }

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    set state(xlib)   $xlib
    set state(room)   $room
    set state(nick)   ""
    set state(users)  {}
    set state(status) disconnected
    set state(args)   {}
    set state(-eventcommand) [namespace code Noop]
    set state(-rostercommand) [namespace code Noop]
    set state(commands) {}
    catch {unset state(id)}

    foreach {key val} $args {
        switch -- $key {
            -eventcommand {
                set state($key) $val
            }
            -rostercommand {
                set state($key) $val
            }
            default {
                unset state
                return -code error \
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::presence::RegisterPresence $xlib $room * \
                           [namespace code [list ParsePresence $token]]
    return $token
}

# ::xmpp::muc::free --

proc ::xmpp::muc::free {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)
    set room $state(room)

    ::xmpp::presence::UnregisterPresence $xlib $room * \
                           [namespace code [list ParsePresence $token]]
    unset state
    return
}

# ::xmpp::muc::join --

proc ::xmpp::muc::join {token nickname args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    # TODO: Add presence options to be able to change presence along with
    # nickname change.
    set commands {}
    set xlist {}
    set history {}
    set newXlist {}
    set state(args) {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
            -xlist {
                set newXlist $val
            }
            -password {
                lappend xlist [::xmpp::xml::create password -cdata $val]
            }
            -maxchars {
                lappend history maxchars $val
            }
            -maxstanzas {
                lappend history maxstanzas $val
            }
            -seconds {
                lappend history seconds $val
            }
            -since {
                lappend history since $val
            }
            -from -
            -show -
            -status -
            -priority {
                lappend state(args) $key $val
            }
            default {
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    if {[llength $history] > 0} {
        lappend xlist [::xmpp::xml::create history -attrs $history]
    }

    lappend newXlist [::xmpp::xml::create x \
                                -xmlns "http://jabber.org/protocol/muc" \
                                -subelements $xlist]

    if {![string equal $state(status) disconnected]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Already joined"]]]]
        return
    }

    set xlib $state(xlib)
    set room $state(room)

    if {[catch {set jid [::xmpp::jid::normalize $room/$nickname]}]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Illegal nickname"]]]]
        return
    }

    set nickname [::xmpp::jid::resource $jid]

    if {[string equal $nickname ""]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Empty nickname"]]]]
        return
    }

    set id [::xmpp::packetID $xlib]
    set state(id) $id
    set state(commands) $commands

    set state(status) connecting
    set state(nick) ""
    set state(users) {}
    array unset state jid,*
    array unset state affiliation,*
    array unset state role,*

    eval [list ::xmpp::sendPresence $xlib \
                        -to $state(room)/$nickname \
                        -xlist $newXlist \
                        -id $id] $state(args)
    return
}

# ::xmpp::muc::leave --

proc ::xmpp::muc::leave {token args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)
    set room $state(room)
    set nick $state(nick)

    set newArgs {}
    foreach {key val} $args {
        switch -- $key {
            -status {
                lappend newArgs -status $val
            }
        }
    }

    set state(nick)   ""
    set state(status) disconnected
    set state(args)   {}

    if {[info exists state(id)]} {
        unset state(id)
        CallBack $state(commands) error \
                 [::xmpp::xml::create error \
                        -cdata [::msgcat::mc "Leaving room"]]
    }

    set state(commands) {}

    eval [list ::xmpp::sendPresence $xlib -type unavailable \
                                          -to $room/$nick] $newArgs
}

# ::xmpp::muc::setNick --

proc ::xmpp::muc::setNick {token nickname args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set commands {}
    set newXlist {}
    array set Args $state(args)
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
            -xlist {
                set newXlist $val
            }
            -maxchars {
                lappend history maxchars $val
            }
            -maxstanzas {
                lappend history maxstanzas $val
            }
            -seconds {
                lappend history seconds $val
            }
            -since {
                lappend history since $val
            }
            -from -
            -show -
            -status -
            -priority {
                set Args($key) $val
            }
            default {
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    switch -- $state(status) {
        disconnected -
        connecting {
            after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "The room isn't\
                                                          joined yet"]]]]
            return
        }
    }

    set xlib $state(xlib)
    set room $state(room)
    set nick $state(nick)

    if {[catch {set jid [::xmpp::jid::normalize $room/$nickname]}]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Illegal nickname"]]]]
        return
    }
    set nickname [::xmpp::jid::resource $jid]

    # Changing nickname to the equivalent one does nothing useful
    if {[::xmpp::jid::equal $room/$nick $room/$nickname]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Nickname didn't\
                                                          change"]]]]
        return
    }

    # Can't change nickname when it is changing already.
    if {[info exists state(id)]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Nickname is changing\
                                                          already"]]]]
        return
    }

    set xlib $state(xlib)
    set room $state(room)
    set nick $state(nick)

    set id [::xmpp::packetID $xlib]
    set state(id) $id
    set state(commands) $commands
    set state(args) [array get Args]

    eval [list ::xmpp::sendPresence $xlib \
                        -to $state(room)/$nickname \
                        -id $id] $state(args)
}

# ::xmpp::muc::ParsePresence --

proc ::xmpp::muc::ParsePresence {token from type xmlElements args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set nick [::xmpp::jid::resource $from]

    switch -- $type {
        available -
        unavailable {
            foreach element $xmlElements {
                ::xmpp::xml::split $element tag xmlns attrs cdata subels
                if {[string equal $xmlns "http://jabber.org/protocol/muc#user"]} {
                    ProcessMUCUser $token $nick $type $subels
                }
            }
        }
        error {
            set error [::xmpp::xml::create error -cdata [::msgcat::mc "Error"]]
            foreach {key val} $args {
                switch -- $key {
                    -id    { set id    $val }
                    -error { set error $val }
                }
            }
            if {[info exists id] && [info exists state(id)] && \
                    [string equal $state(id) $id]} {
                unset state(id)

                switch -- $state(status) {
                    connecting {
                        set state(status) disconnected
                    }
                }

                CallBack $state(commands) error $error
                set state(commands) {}
            }
        }
    }

    switch -- $type {
        unavailable -
        error {
            set status $type

            # Remove user from the room users list
            set idx [lsearch -exact $state(users) $nick]
            if {$idx >= 0} {
                set state(users) [lreplace $state(users) $idx $idx]
            }
            if {[info exists state(ignore_unavailable)] && \
                        [string equal $state(ignore_unavailable) $nick]} {
                unset state(ignore_unavailable)
            } else {
                uplevel #0 $state(-eventcommand) [list exit $nick] $args
            }

            if {[string equal $nick $state(nick)]} {
                set state(nick)   ""
                set state(status) disconnected
                set state(args)   {}

                if {[info exists state(id)]} {
                    unset state(id)
                    CallBack $state(commands) error \
                        [::xmpp::xml::create error \
                            -cdata [::msgcat::mc "Disconnected from the room"]]
                }

                set state(commands) {}

                uplevel #0 $state(-eventcommand) [list disconnect $nick] $args
            }
        }
        available {
            set status $type
            foreach {key val} $args {
                switch -- $key {
                    -id   { set id     $val }
                    -show { set status $val }
                }
            }

            switch -- $state(status) {
                connecting {
                    if {[info exists id] && [info exists state(id)] && \
                            [string equal $id $state(id)]} {
                        unset state(id)
                        set state(status) connected
                        set state(nick) $nick

                        CallBack $state(commands) ok $nick
                        set state(commands) {}
                    }
                }
            }

            # Add user to the room users list
            set idx [lsearch -exact $state(users) $nick]
            if {$idx < 0} {
                lappend state(users) $nick
                set action enter
            } else {
                set action presence
            }

            if {[info exists state(ignore_available)] && \
                    [string equal $state(ignore_available) $nick]} {
                unset state(ignore_available)
            } else {
                uplevel #0 $state(-eventcommand) [list $action $nick] $args
            }
        }
        default {
            return
        }
    }

    # JID, Label, Status
    uplevel #0 $state(-rostercommand) \
               [list $from $nick $status \
                     -affiliation [affiliation $token $nick] \
                     -role [role $token $nick]]
    return
}

# ::xmpp::muc::CallBack --

proc ::xmpp::muc::CallBack {commands status msg} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $msg]
    }
    return
}

# ::xmpp::muc::AttrChanged --

proc ::xmpp::muc::AttrChanged {token nick attr value} {
    variable $token
    upvar 0 $token state

    if {![string equal $value ""] && \
            (![info exists state($attr,$nick)] || \
             ![string equal $value $state($attr,$nick)])} {
        return 1
    } else {
        return 0
    }
}

# ::xmpp::muc::ProcessMUCUser --

proc ::xmpp::muc::ProcessMUCUser {token nick type xmlElements} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels
        switch -- $tag {
            item {
                switch -- $type {
                    available {
                        set args {}
                        set callback 0
                        set jid [::xmpp::xml::getAttr $attrs jid]
                        if {[AttrChanged $token $nick jid $jid]} {
                            lappend args -jid $jid
                            set state(jid,$nick) $jid
                        }
                        set affiliation [::xmpp::xml::getAttr $attrs affiliation]
                        if {[AttrChanged $token $nick affiliation $affiliation]} {
                            lappend args -affiliation $affiliation
                            set state(affiliation,$nick) $affiliation
                            set callback 1
                        }
                        set role [::xmpp::xml::getAttr $attrs role]
                        if {[AttrChanged $token $nick role $role]} {
                            lappend args -role $role
                            set state(role,$nick) $role
                            set callback 1
                        }
                        if {$callback} {
                            uplevel #0 $state(-eventcommand) [list position $nick] $args
                        }
                    }
                    unavailable {
                        set new_nick [::xmpp::xml::getAttr $attrs nick]
                        foreach ch $subels {
                            ::xmpp::xml::split $ch stag sxmlns sattrs scdata ssubels
                            switch -- $stag {
                                reason {
                                    set reason $scdata
                                }
                                actor {
                                    set actor [::xmpp::xml::getAttr $sattrs jid]
                                }
                            }
                        }
                    }
                }
            }
            destroy {
                set args {}
                foreach subel $subels {
                    ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
                    switch -- $stag {
                        reason {
                            lappend args -reason $scdata
                        }
                    }
                }
                set altjid [::xmpp::xml::getAttr $attrs jid]
                if {![string equal $altjid ""]} {
                    lappend args -jid $altjid
                }
                uplevel #0 $state(-eventcommand) [list destroy $nick] $args
            }
        }
    }

    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels
        switch -- $tag {
            status {
                set code [::xmpp::xml::getAttr $attrs code]
                switch -- $code/$type {
                    110/available -
                    210/available {
                        # 110: This present packet is our own
                        # 210: The service has changed our nickname
                        set state(nick) $nick

                        switch -- $state(status) {
                            connecting {
                                catch {unset state(id)}
                                set state(status) connected

                                CallBack $state(commands) ok $nick
                                set state(commands) {}
                            }
                        }
                    }
                }
            }
        }
    }

    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels
        switch -- $tag {
            status {
                set code [::xmpp::xml::getAttr $attrs code]
                switch -- $code {
                    201 {
                        uplevel #0 $state(-eventcommand) [list create $nick]
                    }
                    301 -
                    307 -
                    321 -
                    322 {
                        set args {}
                        # 301: ban, 307: kick, 321: loosing membership
                        # 322: room becomes members-only
                        set RealJID [realJid $token $nick]
                        if {![string equal $RealJID ""]} {
                            lappend args -jid $RealJID
                        }
                        switch -- $code {
                            301 {set action ban}
                            307 {set action kick}
                            321 {set action demember}
                            322 {set action members-only}
                        }

                        if {[info exists actor] && ![string equal $actor ""]} {
                            lappend args -actor $actor
                        }

                        if {[info exists reason] && ![string equal $reason ""]} {
                            lappend args -reason $reason
                        }

                        uplevel #0 $state(-eventcommand) [list $action $nick] $args

                        set state(ignore_unavailable) $nick
                    }
                    303 {
                        # 303: nickname change
                        if {[info exists new_nick] && $new_nick != ""} {
                            if {[string equal $nick $state(nick)]} {
                                # It's our nickname change
                                catch {unset state(id)}
                                set state(nick) $new_nick

                                CallBack $state(commands) ok $new_nick
                                set state(commands) {}
                            }

                            set args [list -nick $new_nick]
                            set RealJID [realJid $token $nick]
                            if {![string equal $RealJID ""]} {
                                lappend args -jid $RealJID
                            }

                            uplevel #0 $state(-eventcommand) [list nick $nick] $args

                            set state(ignore_available) $new_nick
                            set state(ignore_unavailable) $nick
                        }
                    }
                }
            }
        }
    }
}

# ::xmpp::muc::Noop --

proc ::xmpp::muc::Noop {args} {
    return
}

# ::xmpp::muc::realJid --

proc ::xmpp::muc::realJid {token nick} {
    variable $token
    upvar 0 $token state

    if {[info exists state(jid,$nick)]} {
        return $state(jid,$nick)
    } else {
        return ""
    }
}

# ::xmpp::muc::affiliation --

proc ::xmpp::muc::affiliation {token nick} {
    variable $token
    upvar 0 $token state

    if {[info exists state(affiliation,$nick)]} {
        return $state(affiliation,$nick)
    } else {
        return ""
    }
}

# ::xmpp::muc::role --

proc ::xmpp::muc::role {token nick} {
    variable $token
    upvar 0 $token state

    if {[info exists state(role,$nick)]} {
        return $state(role,$nick)
    } else {
        return ""
    }
}

# ::xmpp::muc::nick --

proc ::xmpp::muc::nick {token} {
    variable $token
    upvar 0 $token state

    return $state(nick)
}

# ::xmpp::muc::status --

proc ::xmpp::muc::status {token} {
    variable $token
    upvar 0 $token state

    return $state(status)
}

# ::xmpp::muc::roster --

proc ::xmpp::muc::roster {token args} {
    variable $token
    upvar 0 $token state

    return $state(users)
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
