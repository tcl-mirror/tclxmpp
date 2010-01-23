# blocking.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Simple Communications Blocking (XEP-0191)
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::iq

package provide xmpp::blocking 0.1

namespace eval ::xmpp::blocking {
    namespace export blocklist block unblock register unregister
}

# ::xmpp::blocking::blocklist --
#
#       Request blocking list from the own XMPP server.
#
# Arguments:
#       xlib            XMPP token.
#       -timeout msecs  (optional) Timeout in milliseconds of waiting for
#                       answer.
#       -command cmd    (optional) Command to call back on receiving reply.
#
# Result:
#       ID of outgoing IQ.
#
# Side effects:
#       A blocklist request is sent over the XMPP connection $xlib.

proc ::xmpp::blocking::blocklist {xlib args} {
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

    ::xmpp::sendIQ $xlib get \
	    -query [::xmpp::xml::create blocklist -xmlns urn:xmpp:blocking] \
	    -command [namespace code [list ParseBlocklistAnswer $commands]] \
            -timeout $timeout
}

# ::xmpp::blocking::ParseBlocklistAnswer --
#
#       A helper procedure which is called upon blocklist is received.
#       It calls back the status and error message if any.
#
# Arguments:
#       commands        A list of callbacks to call (only the first of them
#                       is invoked. Status and list of blocked jids or error
#                       stanza are appended to the called command.
#       status          blocking request status (ok, error, abort, timeout).
#       xml             Error message or result.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called if their list isn't empty.

proc ::xmpp::blocking::ParseBlocklistAnswer {commands status xml} {
    if {[llength $commands] == 0} return

    if {[string equal $status ok]} {
        ::xmpp::xml::split $xml tag xmlns attrs cdata subels
        set items {}
        foreach subel $subels {
            ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
            switch -- $stag/$sxmlns {
                item/urn:xmpp:blocking {
                    if {[::xmpp::xml::isAttr $sattrs jid]} {
                        lappend items [::xmpp::xml::getAttr $sattrs jid]
                    }
                }
            }
        }

        uplevel #0 [lindex $commands 0] [list $status $items]
    } else {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# ::xmpp::blocking::block --
#
#       Block specified JIDs. If no JIDs are specified then error is returned.
#
# Arguments:
#       xlib            XMPP token.
#       -jid jid        JID to block (may appear multiple times).
#       -jids jids      List of JIDs to block (may appear multiple times).
#       -timeout msecs  (optional) Timeout in milliseconds of waiting for
#                       answer.
#       -command cmd    (optional) Command to call back on receiving reply.
#
# Result:
#       ID of outgoing IQ.
#
# Side effects:
#       A block request is sent over the XMPP connection $xlib.

proc ::xmpp::blocking::block {xlib args} {
    set commands {}
    set timeout 0
    set items {}
    foreach {key val} $args {
        switch -- $key {
            -jid {
                if {![string equal $val ""]} {
                    lappend items [::xmpp::xml::create item \
                                        -attrs [list jid $val]]
                }
            }
            -jids {
                foreach jid $val {
                    if {![string equal $jid ""]} {
                        lappend items [::xmpp::xml::create item \
                                            -attrs [list jid $jid]]
                    }
                }
            }
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

    if {[llength $items] == 0} {
        return -code error \
               [::msgcat::mc "Nothing to block"]
    }

    ::xmpp::sendIQ $xlib set \
	    -query [::xmpp::xml::create block \
                            -xmlns urn:xmpp:blocking \
                            -subelements $items] \
	    -command [namespace code [list ParseBlockAnswer $commands]] \
            -timeout $timeout
}

# ::xmpp::blocking::ParseBlockAnswer --
#
#       A helper procedure which is called upon block result is received.
#       It calls back the status and error message if any.
#
# Arguments:
#       commands        A list of callbacks to call (only the first of them
#                       is invoked. Status and result or error
#                       stanza are appended to the called command.
#       status          Blocking request status (ok, error, abort, timeout).
#       xml             Error message or result.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called if their list isn't empty.

proc ::xmpp::blocking::ParseBlockAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# ::xmpp::blocking::unblock --
#
#       Unblock specified JIDs. If no JIDs are specified then all blocked JIDs
#       are unblocked.
#
# Arguments:
#       xlib            XMPP token.
#       -jid jid        JID to unblock (may appear multiple times).
#       -jids jids      List of JIDs to unblock (may appear multiple times).
#       -timeout msecs  (optional) Timeout in milliseconds of waiting for
#                       answer.
#       -command cmd    (optional) Command to call back on receiving reply.
#
# Result:
#       ID of outgoing IQ.
#
# Side effects:
#       A block request is sent over the XMPP connection $xlib.

proc ::xmpp::blocking::unblock {xlib args} {
    set commands {}
    set timeout 0
    set items {}
    foreach {key val} $args {
        switch -- $key {
            -jid {
                if {![string equal $val ""]} {
                    lappend items [::xmpp::xml::create item \
                                        -attrs [list jid $val]]
                }
            }
            -jids {
                foreach jid $val {
                    if {![string equal $jid ""]} {
                        lappend items [::xmpp::xml::create item \
                                            -attrs [list jid $jid]]
                    }
                }
            }
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

    ::xmpp::sendIQ $xlib set \
	    -query [::xmpp::xml::create unblock \
                            -xmlns urn:xmpp:blocking \
                            -subelements $items] \
	    -command [namespace code [list ParseUnblockAnswer $commands]] \
            -timeout $timeout
}

# ::xmpp::blocking::ParseUnblockAnswer --
#
#       A helper procedure which is called upon unblock result is received.
#       It calls back the status and error message if any.
#
# Arguments:
#       commands        A list of callbacks to call (only the first of them
#                       is invoked. Status and result or error
#                       stanza are appended to the called command.
#       status          Unblocking request status (ok, error, abort, timeout).
#       xml             Error message or result.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called if their list isn't empty.

proc ::xmpp::blocking::ParseUnblockAnswer {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    }
    return
}

# ::xmpp::blocking::register --
#
#       Register handler to process blocking IQ pushes.
#
# Arguments:
#       -command cmd    (optional) Command to call when blocking push is
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
#       XMPP blocking push callback is registered.

proc ::xmpp::blocking::register {args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::iq::register set * urn:xmpp:blocking \
                         [namespace code [list ParsePush $commands]]
    return
}

# ::xmpp::blocking::ParsePush --
#
#       A helper procedure which is called on any incoming XMPP blocking request.
#       It either calls a command specified during registration or simply
#       returns result (if there weren't any command).
#
# Arguments:
#       commands            A list of commands to call (only the first one
#                           will be invoked).
#       xlib                XMPP token where request was received.
#       from                JID of user who sent the request.
#       xml                 Request XML element (in blocking requests it is empty).
#       args                optional arguments (-lang, -to, -id).
#
# Result:
#       Either {result, {}}, or {error type condition}, or empty string, if
#       the application desided to reply later.
#
# Side effects:
#       Side effects of the called command.

proc ::xmpp::blocking::ParsePush {commands xlib from xml args} {
    # -to attribute contains the own JID, so check from JID to prevent
    # malicious users to pretend they perform blocking push
    set to [::xmpp::xml::getAttr $args -to]

    if {![string equal $from ""] && \
            ![::xmpp::jid::equal $from $to] && \
            ![::xmpp::jid::equal $from [::xmpp::jid::stripResource $to]] && \
            ![::xmpp::jid::equal $from [::xmpp::jid::server $to]]} {

        return [list error cancel service-unavailable]
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    switch -- $tag/$xmlns {
        block/urn:xmpp:blocking -
        unblock/urn:xmpp:blocking {}
        default {
            return [list error modify bad-request]
        }
    }

    set items {}
    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
        switch -- $stag/$sxmlns {
            item/urn:xmpp:blocking {
                if {[::xmpp::xml::isAttr $sattrs jid]} {
                    lappend items [::xmpp::xml::getAttr $sattrs jid]
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        return [uplevel #0 [lindex $commands 0] [list $xlib $tag $items] $args]
    } else {
        return [list result {}]
    }
}

# ::xmpp::blocking::unregister --
#
#       Unregister handler which used to answer XMPP blocking IQ pushes.
#
# Arguments:
#       None.
#
# Result:
#       Empty string.
#
# Side effects:
#       XMPP blocking push callback is registered.

proc ::xmpp::blocking::unregister {} {
    ::xmpp::iq::unregister set * urn:xmpp:blocking

    return
}

# vim:ts=8:sw=4:sts=4:et
