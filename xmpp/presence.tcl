# presence.tcl --
#
#       This file is part of the XMPP library. It implements the presence
#       processing for high level applications. If you want to use low level
#       parsing, use -packetCommand option for ::xmpp::new.
#
# Copyright (c) 2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::presence 0.1

namespace eval ::xmpp::presence {
    namespace export register unregister process
}

# ::xmpp::presence::register --
#
#       Register presence callback.
#
# Arguments:
#       type            Presence type to register. Must be one of known
#                       presence types (available, error, probe, subscribe,
#                       subscribed, unavailable, unsubscribe, unsubscribed)
#                       or *.
#       cmd             Command to call when a registered presence is received.
#                       The return value of the command is ignored.
#
# Result:
#       Empty string or error if presence type isn't a valid type.
#
# Side effects:
#       A presence callback is registered.

proc ::xmpp::presence::register {type cmd} {
    RegisterPresence * * $type $cmd
}

# ::xmpp::presence::unregister --
#
#       Unregister presence callback.
#
# Arguments:
#       type            Presence type to unregister. Must be one of known
#                       presence types (available, error, probe, subscribe,
#                       subscribed, unavailable, unsubscribe, unsubscribed)
#                       or *.
#       cmd             Command to remove from registered commands.
#
# Result:
#       Empty string.
#
# Side effects:
#       A presence callback is unregistered.

proc ::xmpp::presence::unregister {type cmd} {
    UnregisterPresence * * $type $cmd
}

# ::xmpp::presence::RegisterPresence --
#
#       Register presence callback.
#
# Arguments:
#       xlib            XMPP token pattern.
#       jid             Presence from address.
#       type            Presence type to register. Must be one of known
#                       presence types (available, error, probe, subscribe,
#                       subscribed, unavailable, unsubscribe, unsubscribed)
#                       or *.
#       cmd             Command to call when a registered presence is received.
#                       The return value of the command is ignored.
#
# Result:
#       Empty string or error if presence type isn't a valid type.
#
# Side effects:
#       A presence callback is registered.

proc ::xmpp::presence::RegisterPresence {xlib jid type cmd} {
    variable PresenceCmd

    set jid [::xmpp::jid::normalize $jid]

    switch -- $type {
        available -
        error -
        probe -
        subscribe -
        subscribed -
        unavailable -
        unsubscribe -
        unsubscribed -
        * {}
        default {
            return -code error [::msgcat::mc "Illegal presence type \"%s\"" $type]
        }
    }

    if {![info exists PresenceCmd($xlib,$type,$jid)]} {
        set PresenceCmd($xlib,$type,$jid) {}
    }
    if {[lsearch -exact $PresenceCmd($xlib,$type,$jid) $cmd] < 0} {
        lappend PresenceCmd($xlib,$type,$jid) $cmd
    }
    return
}

# ::xmpp::presence::UnregisterPresence --
#
#       Unregister presence callback.
#
# Arguments:
#       xlib            XMPP token pattern.
#       jid             Presence from address.
#       type            Presence type to unregister. Must be one of known
#                       presence types (available, error, probe, subscribe,
#                       subscribed, unavailable, unsubscribe, unsubscribed)
#                       or *.
#       cmd             Command to remove from registered commands.
#
# Result:
#       Empty string.
#
# Side effects:
#       A presence callback is unregistered.

proc ::xmpp::presence::UnregisterPresence {xlib jid type cmd} {
    variable PresenceCmd

    set jid [::xmpp::jid::normalize $jid]

    if {![info exists PresenceCmd($xlib,$type,$jid)]} {
        return
    }

    if {[set idx [lsearch -exact $PresenceCmd($xlib,$type,$jid) $cmd]] >= 0} {
        set PresenceCmd($xlib,$type,$jid) \
            [lreplace $PresenceCmd($xlib,$type,$jid) $idx $idx]

        if {[llength $PresenceCmd($xlib,$type,$jid)] == 0} {
            unset PresenceCmd($xlib,$type,$jid)
        }
    }
    return
}

# ::xmpp::presence::process --
#
#       Sequentially call all registered presence callbacks.
#
# Arguments:
#       xlib            XMPP token.
#       from            JID from which the presence is received.
#       type            Presence type.
#       xmlElements     XML elements included into the presence stanza.
#           The rest of args are optional.
#       -x xparams      {key value} list of unspecified attributes.
#       -lang lang      Stanza language (value of xml:lang attribute).
#       -to to          Value of to attribute.
#       -id id          Value of id attribute
#       -priority prio  Presence priority.
#       -show show      Presence status (chat, away, xa, dnd)
#       -status status  Text status description.
#       -error xml      Error subelement.
#
# Result:
#       Empty string.
#
# Side effects:
#       Commands corresponding to received presence are called.

proc ::xmpp::presence::process {xlib from type xmlElements args} {
    variable PresenceCmd

    if {[string equal $type ""]} {
        set type available
    }

    ::xmpp::Debug $xlib 2 "$from $type $xmlElements $args"

    set jid [::xmpp::jid::normalize $from]
    set bjid [::xmpp::jid::removeResource $jid]
    set commands {}

    foreach xidx [list $xlib *] {
        foreach tidx [list $type *] {
            foreach jidx [list $jid $bjid *] {
                if {[info exists PresenceCmd($xidx,$tidx,$jidx)]} {
                    set commands \
                        [concat $commands $PresenceCmd($xidx,$tidx,$jidx)]
                }
            }
        }
    }

    foreach cmd $commands {
        ::xmpp::Debug $xlib 2 "calling $cmd"
        uplevel #0 $cmd [list $from $type $xmlElements] $args
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
