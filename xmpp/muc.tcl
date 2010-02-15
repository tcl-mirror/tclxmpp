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

    set state(xlib)           $xlib
    set state(room)           $room
    set state(nick)           ""
    set state(requestedNick)  ""
    set state(users)          {}
    set state(status)         disconnected
    set state(args)           {}
    set state(-eventcommand)  [namespace code Noop]
    set state(-rostercommand) [namespace code Noop]
    set state(commands)       {}
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

    if {[string equal $state(status) connected]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Already joined"]]]]
        return
    }

    if {[string equal $state(status) connecting]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Already joining"]]]]
        return
    }

    set xlib $state(xlib)
    set room $state(room)

    if {[catch {set jid [::xmpp::jid::normalize \
                                [::xmpp::jid::replaceResource $room \
                                                              $nickname]]}]} {
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
    set state(requestedNick) $nickname
    set state(users) {}
    array unset state jid,*
    array unset state affiliation,*
    array unset state role,*

    eval [list ::xmpp::sendPresence $xlib \
                        -to [::xmpp::jid::replaceResource $room $nickname] \
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

    set state(status) disconnected
    set state(args) {}

    if {[info exists state(id)]} {
        unset state(id)
        CallBack $state(commands) error \
                 [::xmpp::xml::create error \
                        -cdata [::msgcat::mc "Leaving room"]]
    }

    set id [::xmpp::packetID $xlib]
    set state(commands) {}

    eval [list ::xmpp::sendPresence $xlib \
                        -type unavailable \
                        -to [::xmpp::jid::replaceResource $room $nick] \
                        -id $id] $newArgs
}

# ::xmpp::muc::reset --

proc ::xmpp::muc::reset {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set state(status) disconnected
    set state(args) {}

    catch {unset state(id)}
    set state(commands) {}
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

    if {[catch {set jid [::xmpp::jid::normalize \
                                [::xmpp::jid::replaceResource $room \
                                                              $nickname]]}]} {
        after idle [namespace code \
                        [list CallBack $commands error \
                              [::xmpp::xml::create error \
                                    -cdata [::msgcat::mc "Illegal nickname"]]]]
        return
    }
    set nickname [::xmpp::jid::resource $jid]

    # Changing nickname to the equivalent one does nothing useful
    if {[::xmpp::jid::equal [::xmpp::jid::replaceResource $room $nick] \
                            [::xmpp::jid::replaceResource $room $nickname]]} {
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
                        -to [::xmpp::jid::replaceResource $room $nickname] \
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
                if {[string equal $xmlns \
                                  "http://jabber.org/protocol/muc#user"]} {
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
            if {[info exists state(id)]} {
                # We're waiting for some answer

                set match 0
                if {[info exists id] && [string equal $state(id) $id]} {
                    # If id matches then it's definitely an answer

                    set match 1
                } elseif {![info exists id]} {
                    # If there's no id then it may be an answer if the room
                    # doesn't respect XMPP rules

                    switch -- $state(status) {
                        connecting {
                            set nickname $state(requestedNick)
                        }
                        default {
                            set nickname $state(nick)
                        }
                    }

                    if {[string equal $nick $nickname]} {
                        # TODO: Should we also check for empty $nick?

                        set match 1
                    }
                }

                if {$match} {
                    unset state(id)

                    switch -- $state(status) {
                        connecting {
                            set state(status) disconnected
                        }
                    }

                    CallBack $state(commands) error $error
                    set state(commands) {}
                    return
                }
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

            catch {unset state(jid,$nick)}
            catch {unset state(affiliation,$nick)}
            catch {unset state(role,$nick)}

            if {[info exists state(ignore_unavailable)] && \
                        [string equal $state(ignore_unavailable) $nick]} {
                unset state(ignore_unavailable)
            } else {
                uplevel #0 $state(-eventcommand) [list exit $nick] $args
            }

            if {[string equal $nick $state(nick)]} {
                # TODO: Check for $state(requestedNick)?
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

            if {[info exists state(id)]} {
                set match 0
                if {[info exists id] && [string equal $id $state(id)]} {
                    set match 1
                } elseif {![info exists id]} {
                    switch -- $state(status) {
                        connecting {
                            set nickname $state(requestedNick)
                        }
                        default {
                            set nickname $state(nick)
                        }
                    }

                    if {[string equal $nick $nickname]} {
                        set match 1
                    }
                }

                if {$match} {
                    unset state(id)
                    set state(status) connected
                    set state(nick) $nick

                    CallBack $state(commands) ok $nick
                    set state(commands) {}
                }
            }

            # Add user to the room users list
            set idx [lsearch -exact $state(users) $nick]
            if {$idx < 0} {
                lappend state(users) $nick
                set action enter
                if {[string equal [set RealJID [realJid $token $nick]] ""]} {
                    lappend args -jid $RealJID
                }
                if {[string equal [set aff [affiliation $token $nick]] ""]} {
                    lappend args -affiliation $aff
                }
                if {[string equal [set role [role $token $nick]] ""]} {
                    lappend args -role $role
                }
            } else {
                set action presence
            }

            if {[info exists state(ignore_available)] && \
                    [string equal $state(ignore_available) $nick]} {
                uplevel #0 $state(-eventcommand) nick $state(nick_args)
                unset state(nick_args)
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
                        if {![string equal $jid ""]} {
                            lappend args -jid $jid
                            set state(jid,$nick) $jid
                        }
                        set affiliation \
                            [::xmpp::xml::getAttr $attrs affiliation]
                        if {[AttrChanged $token $nick affiliation \
                                                      $affiliation]} {
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
                        if {$callback && \
                                [lsearch -exact $state(users) $nick] >= 0} {
                            uplevel #0 $state(-eventcommand) \
                                       [list position $nick] $args
                        }
                    }
                    unavailable {
                        set new_nick [::xmpp::xml::getAttr $attrs nick]
                        foreach subel $subels {
                            ::xmpp::xml::split $subel stag sxmlns sattrs \
                                                      scdata ssubels
                            switch -- $stag {
                                reason {
                                    set reason $scdata
                                }
                                actor {
                                    set actor \
                                        [::xmpp::xml::getAttr $sattrs jid]
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

                        if {[info exists reason] && \
                                            ![string equal $reason ""]} {
                            lappend args -reason $reason
                        }

                        uplevel #0 $state(-eventcommand) \
                                   [list $action $nick] $args

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

                            set state(ignore_available) $new_nick
                            set state(nick_args) [linsert $args 0 $nick]
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
    UserAttr $token jid $nick
}

# ::xmpp::muc::affiliation --

proc ::xmpp::muc::affiliation {token nick} {
    UserAttr $token affiliation $nick
}

# ::xmpp::muc::role --

proc ::xmpp::muc::role {token nick} {
    UserAttr $token role $nick
}

# ::xmpp::muc::UserAttr --

proc ::xmpp::muc::UserAttr {token attr nick} {
    variable $token
    upvar 0 $token state

    if {[info exists state($attr,$nick)]} {
        return $state($attr,$nick)
    } else {
        return ""
    }
}

# ::xmpp::muc::nick --

proc ::xmpp::muc::nick {token} {
    Attr $token nick
}

# ::xmpp::muc::status --

proc ::xmpp::muc::status {token} {
    Attr $token status
}

# ::xmpp::muc::roster --

proc ::xmpp::muc::roster {token} {
    Attr $token users
}

# ::xmpp::muc::Attr --

proc ::xmpp::muc::Attr {token attr} {
    variable $token
    upvar 0 $token state

    return $state($attr)
}

# ::xmpp::muc::setAffiliation --

proc ::xmpp::muc::setAffiliation {xlib room affiliation args} {
    eval [list SetAttr $xlib $room affiliation $affiliation] $args
}

# ::xmpp::muc::setRole --

proc ::xmpp::muc::setRole {xlib room role args} {
    eval [list SetAttr $xlib $room role $role] $args
}

# ::xmpp::muc::SetAttr --

proc ::xmpp::muc::SetAttr {xlib room attr value args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -nick    { set nick $val }
            -jid     { set jid $val }
            -reason  { set reason $val }
            -command { set commands [list $val] }
        }
    }

    if {[info exists reason]} {
        set subels [list [::xmpp::xml::create reason -cdata $reason]]
    } else {
        set subels {}
    }

    if {[info exists nick]} {
        set attrs [list nick $nick $attr $value]
    } elseif {[info exists jid]} {
        set attrs [list jid $jid $attr $value]
    } else {
        return -code error \
               [::msgcat::mc "Option \"-nick\" or \"-jid\" must be specified"]
    }

    set item [::xmpp::xml::create item \
                        -attrs $attrs \
                        -subelements $subels]

    ::xmpp::sendIQ $xlib set \
            -query [::xmpp::xml::create query \
                            -xmlns "http://jabber.org/protocol/muc#admin" \
                            -subelement $item] \
            -to $room \
            -command [namespace code [list CallBack $commands]]
}

# ::xmpp::muc::CompareAffiliations --

proc ::xmpp::muc::CompareAffiliations {affiliation1 affiliation2} {
    set affiliations {outcast none member admin owner}

    set idx1 [lsearch -exact $affiliations $affiliation1]
    set idx2 [lsearch -exact $affiliations $affiliation2]
    expr {$idx1 - $idx2}
}

# ::xmpp::muc::CompareRoles --

proc ::xmpp::muc::CompareRoles {role1 role2} {
    set roles {none visitor participant moderator}

    set idx1 [lsearch -exact $roles $role1]
    set idx2 [lsearch -exact $roles $role2]
    expr {$idx1 - $idx2}
}

# ::xmpp::muc::raiseAffiliation --

proc ::xmpp::muc::raiseAffiliation {token nick value args} {
    eval [list RaiseOrLowerAttr $token $nick affiliation $value 1] $args
}

# ::xmpp::muc::raiseRole --

proc ::xmpp::muc::raiseRole {token nick value args} {
    eval [list RaiseOrLowerAttr $token $nick role $value 1] $args
}

# ::xmpp::muc::lowerAffiliation --

proc ::xmpp::muc::lowerAffiliation {token nick value args} {
    eval [list RaiseOrLowerAttr $token $nick affiliation $value -1] $args
}

# ::xmpp::muc::lowerRole --

proc ::xmpp::muc::lowerRole {token nick value args} {
    eval [list RaiseOrLowerAttr $token $nick role $value -1] $args
}

# ::xmpp::muc::RaiseOrLowerAttr --

proc ::xmpp::muc::RaiseOrLowerAttr {token nick attr value dir args} {
    variable $token
    upvar 0 $token state

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -reason  { set reason $val }
            -command { set commands [list $val] }
        }
    }

    if {![info exists state(xlib)]} {
        CallBack $commands error \
                 [::xmpp::xml::create error \
                            -cdata [::msgcat::mc "MUC token doesn't exist"]]
        return
    }

    set xlib $state(xlib)
    set room $state(room)

    switch -- $state(status) {
        disconnected {
            CallBack $commands error \
                     [::xmpp::xml::create error \
                            -cdata [::msgcat::mc "Must join room first"]]
            return
        }
    }

    switch -- $attr {
        affiliation {
            set value0 [affiliation $token $nick]
            set diff [CompareAffiliations $value0 $value]
        }
        role {
            set value0 [role $token $nick]
            set diff [CompareRoles $value0 $value]
        }
    }

    if {($dir > 0 && $diff >= 0) || ($dir < 0 && $diff <= 0)} {
        CallBack $commands error \
                 [::xmpp::xml::create error \
                            -cdata [::msgcat::mc "User already %s" $value0]]
        return
    }

    set attrs [list -nick $nick]

    switch -- $attr/$value {
        affiliation/outcast {
            # Banning request MUST be based on user's bare JID (which though 
            # may be not known by admin)
            set RealJID [realJid $token $nick]
            if {![string equal $RealJID ""]} {
                set attrs [list -jid [::xmpp::jid::removeResource $RealJID]]
            }
        }
    }

    eval [list SetAttr $xlib $room $attr $value] $attrs $args
}

# ::xmpp::muc::requestAffiliations --

proc ::xmpp::muc::requestAffiliations {xlib room value args} {
    eval [list RequestList $xlib $room affiliation $value] $args
}

# ::xmpp::muc::requestRoles --

proc ::xmpp::muc::requestRoles {xlib room value args} {
    eval [list RequestList $xlib $room role $value] $args
}

# ::xmpp::muc::RequestList --

proc ::xmpp::muc::RequestList {xlib room attr value args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    ::xmpp::sendIQ $xlib get \
            -query [::xmpp::xml::create query \
                            -xmlns "http://jabber.org/protocol/muc#admin" \
                            -subelement [::xmpp::xml::create item \
                                                -attrs [list $attr $value]]] \
            -to $room \
            -command [namespace code [list ParseRequestList $commands $attr]]
}

# ::xmpp::muc::ParseRequestList --

proc ::xmpp::muc::ParseRequestList {commands attr status xml} {
    if {![string equal $status ok]} {
        CallBack $commands $status $xml
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set items {}
    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
        switch -- $stag {
            item {
                set nick [::xmpp::xml::getAttr $sattrs nick]
                set jid [::xmpp::xml::getAttr $sattrs jid]
                switch -- $attr {
                    affiliation {
                        set attribute \
                            [::xmpp::xml::getAttr $sattrs affiliation]
                    }
                    role {
                        set attribute [::xmpp::xml::getAttr $sattrs role]
                    }
                }
                set reason ""
                foreach ssubel $ssubels {
                    ::xmpp::xml::split $ssubel sstag ssxmlns ssattrs \
                                               sscdata sssubels
                    switch -- $sstag {
                        reason {
                            set reason $sscdata
                        }
                    }
                }
                lappend items [list $nick $jid $attribute $reason]
            }
        }
    }

    CallBack $commands ok $items
    return
}

# ::xmpp::muc::sendAffiliations --

proc ::xmpp::muc::sendAffiliations {xlib room items args} {
    eval [list SendList $xlib $room affiliation $items] $args
}

# ::xmpp::muc::sendRoles --

proc ::xmpp::muc::sendRoles {xlib room items args} {
    eval [list SendList $xlib $room role $items] $args
}

# ::xmpp::muc::SendList --

proc ::xmpp::muc::SendList {xlib room attr items args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    set subels {}
    foreach item $items {
        foreach {nick jid attribute reason} $item break

        if {[string equal $nick ""] && [string equal $jid ""]} continue

        set attrs [list $attr $attribute]
        if {![string equal $nick ""]} {
            lappend attrs nick $nick
        }
        if {![string equal $jid ""]} {
            lappend attrs jid $jid
        }
        if {![string equal $reason ""]} {
            set ssubels [list [::xmpp::xml::create reason -cdata $reason]]
        } else {
            set ssubels {}
        }
        lappend subels [::xmpp::xml::create item \
                                -attrs $attrs \
                                -subelements $ssubels]
    }

    ::xmpp::sendIQ $xlib set \
            -query [::xmpp::xml::create query \
                            -xmlns "http://jabber.org/protocol/muc#admin" \
                            -subelements $subels] \
            -to $room \
            -command [namespace code [list CallBack $commands]]
}

# ::xmpp::muc::unsetOutcast --

proc ::xmpp::muc::unsetOutcast {xlib room jid args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    RequestList $xlib $room affiliation outcast \
                -command [namespace code [list ParseOutcastList \
                                               $xlib $room $jid $commands]]
}

# ::xmpp::muc::ParseOutcastList --

proc ::xmpp::muc::ParseOutcastList {xlib room jid commands status items} {
    if {![string equal $status ok]} {
        CallBack $commands $status $items
        return
    }

    set bjid [xmpp::jid::normalize [::xmpp::jid::removeResource $jid]]
    set found 0
    foreach item $items {
        foreach {nick jid affiliation reason} $item break

        if {[string equal $jid $bjid]} {
            set found 1
            break
        }
    }

    if {!$found} {
        CallBack $commands error \
                 [::xmpp::xml::create error \
                            -cdata [::msgcat::mc "User is not banned"]]
        return
    }

    set item [::xmpp::xml::create item \
                    -attrs [list jid $bjid affiliation none]]

    ::xmpp::sendIQ $xlib set \
            -query [::xmpp::xml::create query \
                            -xmlns "http://jabber.org/protocol/muc#admin" \
                            -subelement $item] \
            -to $room \
            -command [namespace code [list CallBack $commands]]
}

# ::xmpp::muc::destroy --

proc ::xmpp::muc::destroy {xlib room args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -jid     { set jid $val }
            -reason  { set reason $val }
            -command { set commands [list $val] }
        }
    }

    if {[info exists jid]} {
        set attrs [list jid $jid]
    } else {
        set attrs {}
    }

    if {[info exists reason]} {
        set subels [list [::xmpp::xml::create reason -cdata $reason]]
    } else {
        set subels {}
    }

    ::xmpp::sendIQ $xlib set \
            -query [::xmpp::xml::create query \
                            -xmlns "http://jabber.org/protocol/muc#owner" \
                            -subelement [::xmpp::xml::create destroy \
                                                -attrs $attrs \
                                                -subelements $subels]] \
            -to $room \
            -command [namespace code [list CallBack $commands]]
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
