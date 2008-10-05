#  starttls.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       tls network socket security layer.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# $Id$

package require xmpp::stanzaerror
package require xmpp::transport::tls

package provide xmpp::starttls 0.1

namespace eval ::xmpp::starttls {}

##########################################################################

proc ::xmpp::starttls::starttls {xlib args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    ::xmpp::Debug 2 $xlib "$token"

    array unset state
    set state(xlib) $xlib
    set state(tlsArgs) {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -cacertstore -
            -cadir       -
            -cafile      -
            -certfile    -
            -keyfile     -
            -password    {
                lappend state(tlsArgs) $key $val
            }
            -callback    {
                lappend state(tlsArgs) -command $val
            }
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            default {
                unset state
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::RegisterElement $xlib * urn:ietf:params:xml:ns:xmpp-tls \
                            [namespace code [list Parse $token]]

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortStarttls $token timeout \
                                    [::msgcat::mc "STARTTLS timed out"]]]]
    }

    ::xmpp::TraceStreamFeatures $xlib \
                                [namespace code [list Continue $token]]

    if {[info exists state(-command)]} {
        # Asynchronous mode
        return $token
    } else {
        # Synchronous mode
        vwait $token\(status)

        set status $state(status)
        set msg $state(msg)
        unset state

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

# ::xmpp::starttls::abort --
#
#       Abort an existing STARTTLS procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           STARTTLS control token which is returned by
#                       ::xmpp::starttls::starttls procedure.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::starttls::abort {token} {
    AbortStarttls $token abort [::msgcat::mc "STARTTLS aborted"]
}

# ::xmpp::starttls::AbortStarttls --
#
#       Abort an existing STARTTLS procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           STARTTLS control token which is returned by
#                       ::xmpp::starttls::starttls procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::starttls::AbortStarttls {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug 2 $xlib "$token"

    # TODO: abort stream reopening

    ::xmpp::RemoveTraceStreamFeatures $xlib \
                                [namespace code [list Continue $token]]

    Finish $token $status [::xmpp::xml::create error -cdata $msg]
}

##########################################################################

proc ::xmpp::starttls::Continue {token featuresList} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug 2 $xlib "$token"

    set starttlsFeature 0
    foreach feature $featuresList {
        ::xmpp::xml::split $feature tag xmlns attrs cdata subels

        switch -- $tag/$xmlns {
            starttls/urn:ietf:params:xml:ns:xmpp-tls {
                set starttlsFeature 1
                break
            }
        }
    }

    if {!$starttlsFeature} {
        Finish $token error \
               [::xmpp::stanzaerror::error modify not-acceptable -text \
                     [::msgcat::mc "Server haven't provided STARTTLS feature"]]
        return
    }

    ::xmpp::outXML $xlib [::xmpp::xml::create starttls \
                                    -xmlns urn:ietf:params:xml:ns:xmpp-tls]
}

##########################################################################

proc ::xmpp::starttls::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug 2 $xlib "$token"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        proceed {
            Proceed $token
        }
        failure {
            Failure $token $subels
        }
    }
}

##########################################################################

proc ::xmpp::starttls::Proceed {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug 2 $xlib "$token"

    eval [list ::xmpp::SwitchTransport $xlib tls] $state(tlsArgs)

    # TODO
    #if {[catch {eval [list ::xmpp::transport::tcp::toTLS $state(xlib)] \
    #                 $args} msg]} {
    #    set err [::xmpp::stanzaerror::error modify undefined-condition -text $msg]
    #    Finish $token error $err
    #    return
    #}

    ::xmpp::ReopenStream $state(xlib) -command #

    Finish $token ok {}
}

##########################################################################

proc ::xmpp::starttls::Failure {token xmlElements} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug 2 $xlib "$token"

    set error [lindex $xmlElements 0]
    if {[string equal $error ""]} {
        set err [::xmpp::stanzaerror::error modify undefined-condition \
                        -text [::msgcat::mc "STARTTLS failed"]]
    } else {
        ::xmpp::xml::split $error tag xmlns attrs cdata subels
        set err [::xmpp::stanzaerror::error modify $tag]
    }
    Finish $token error $err
}

##########################################################################

proc ::xmpp::starttls::Finish {token status xmlData} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Debug 2 $xlib "$token $status"

    ::xmpp::UnregisterElement $xlib * urn:ietf:params:xml:ns:xmpp-tls

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    if {[string equal $status ok]} {
        set msg ""
        ::xmpp::client $xlib status [::msgcat::mc "STARTTLS successful"]
    } else {
        set msg [::xmpp::stanzaerror::message $xmlData]
        ::xmpp::client $xlib status [::msgcat::mc "STARTTLS failed"]
    }

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $msg]
    } else {
        # Synchronous mode
        set state(msg) $msg
        # Trigger vwait in [starttls]
        set state(status) $status
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
