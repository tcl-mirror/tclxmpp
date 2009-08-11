# ping.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       XMPP Ping (XEP-0199)
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::ping 0.1

namespace eval ::xmpp::ping {
    namespace export ping register unregister
}

# ::xmpp::ping::ping --
#
#       Send XMPP ping IQ request to a specified JID.
#
# Arguments:
#       xlib            XMPP token.
#       -to jid         (optional) JID to send ping request. If empty then
#                       the request is sent without 'to' attribute which
#                       means sending to own bare JID.
#       -timeout msecs  (optional) Timeout in milliseconds of waiting for
#                       answer.
#       -command cmd    (optional) Command to call back on receiving reply.
#
# Result:
#       ID of outgoing IQ.
#
# Side effects:
#       A ping packet is sent over the XMPP connection $xlib.

proc ::xmpp::ping::ping {xlib args} {
    set commands {}
    set newArgs {}
    foreach {key val} $args {
        switch -- $key {
            -to {
                lappend newArgs -to $val
            }
            -timeout {
                lappend newArgs -timeout $val
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

    eval [list ::xmpp::sendIQ $xlib get \
	            -query [::xmpp::xml::create ping -xmlns urn:xmpp:ping] \
	            -command [namespace code [list ParseAnswer $commands]]] \
               $newArgs
}

# ::xmpp::ping::ParseAnswer --
#
#       A helper procedure which is called upon XMPP ping answer is received.
#       It calls back the status and error message if any.
#
# Arguments:
#       commands        A list of callbacks to call (only the first of them
#                       is invoked. Status and error stanza are appended to
#                       the called command.
#       status          Ping request status (ok, error, abort, timeout).
#       xml             Error message or result.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called if their list isn't empty.

proc ::xmpp::ping::ParseAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# ::xmpp::ping::register --
#
#       Register handler to answer XMPP ping IQ requests.
#
# Arguments:
#       -command cmd    (optional) Command to call when ping request is
#                       arrived. The result of the command is sent back.
#                       It must be either {result {}}, or {error type condition},
#                       or empty string if the application will reply to the
#                       request separately.
#                       The command's arguments are xlib, from, xml, and
#                       optional parameters -to, -id, -lang.
#
# Result:
#       Empty string.
#
# Side effects:
#       XMPP ping callback is registered.

proc ::xmpp::ping::register {args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::iq::register get ping urn:xmpp:ping \
                         [namespace code [list ParseRequest $commands]]
    return
}

# ::xmpp::ping::ParseRequest --
#
#       A helper procedure which is called on any incoming XMPP ping request.
#       It either calls a command specified during registration or simply
#       returns result (if there weren't any command).
#
# Arguments:
#       commands            A list of commands to call (only the first one
#                           will be invoked).
#       xlib                XMPP token where request was received.
#       from                JID of user who sent the request.
#       xml                 Request XML element (in ping requests it is empty).
#       args                optional arguments (-lang, -to, -id).
#
# Result:
#       Either {result, {}}, or {error type condition}, or empty string, if
#       the application desided to reply later.
#
# Side effects:
#       Side effects of the called command.

proc ::xmpp::ping::ParseRequest {commands xlib from xml args} {
    if {[llength $commands] > 0} {
        return [uplevel #0 [lindex $commands 0] [list $xlib $from] $args]
    } else {
        return [list result {}]
    }
}

# ::xmpp::ping::unregister --
#
#       Unregister handler which used to answer XMPP ping IQ requests.
#
# Arguments:
#       None.
#
# Result:
#       Empty string.
#
# Side effects:
#       XMPP ping callback is registered.

proc ::xmpp::ping::unregister {} {
    ::xmpp::iq::unregister get ping urn:xmpp:ping

    return
}

# vim:ts=8:sw=4:sts=4:et
