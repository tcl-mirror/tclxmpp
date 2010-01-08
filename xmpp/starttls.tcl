# starttls.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       tls network socket security layer.
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::stanzaerror
package require xmpp::transport::tls

package provide xmpp::starttls 0.1

namespace eval ::xmpp::starttls {}

# ::xmpp::starttls::starttls --
#
#       Negotiate STARTTLS procedure and switch to an encrypted stream.
#
# Arguments:
#       xlib                    XMPP token. It must be connected and XMPP
#                               stream must be opened.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for STARTTLS
#                               negotiation.
#       -command    callback    (optional) If present, it turns on asynchronous
#                               mode. After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and either new stream session ID if
#                               status is "ok", or error stanza otherwise.
#       -verifycommand          TLS callback (it turns into -command option
#                               for ::tls::import).
#       -infocommand            Callback to get status of an established
#                               TLS connection. It is calles wit a list of
#                               key-value pairs returned from tls::status.
#       -castore                If this option points to a file then it's
#                               equivalent to -cafile, if it points to a
#                               directory then it's equivalent to -cadir.
#
#       -cadir                  Options for ::tls::import procedure (see
#       -cafile                 tls package manual for details).
#       -certfile
#       -keyfile
#       -ssl2
#       -ssl3
#       -tls1
#       -request
#       -require
#       -password
#
# Result:
#       In asynchronous mode a control token is returned (it allows to abort
#       STARTTLS process). In synchronous mode either new stream session ID is
#       returned (if STARTTLS succeded) or IQ error (with return code
#       error in case of error, or break in case of abortion).
#
# Side effects:
#       A variable in ::xmpp::starttls namespace is created and STARTTLS state
#       is stored in it in asynchronous mode. In synchronous mode the Tcl event
#       loop is entered and processing until return.

proc ::xmpp::starttls::starttls {xlib args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::Set $xlib abortCommand [namespace code [abort $token]]

    set state(xlib) $xlib
    set state(tlsArgs) {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -castore       -
            -cadir         -
            -cafile        -
            -certfile      -
            -keyfile       -
            -ssl2          -
            -ssl3          -
            -tls1          -
            -request       -
            -require       -
            -password      -
            -verifycommand -
            -infocommand   {
                lappend state(tlsArgs) $key $val
            }
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            default {
                unset state
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
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

        foreach {status msg} $state(status) break
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

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::RemoveTraceStreamFeatures $xlib \
                                [namespace code [list Continue $token]]

    if {[info exists state(reopenStream)]} {
        ::xmpp::GotStream $xlib abort {}
        return
    }

    Finish $token $status [::xmpp::xml::create error -cdata $msg]
}

# ::xmpp::starttls::Continue --
#
#       A helper procedure which checks if there is a STARTTLS feature in a
#       features list provided by server and continues or finishes STARTTLS
#       negotiation.
#
# Arguments:
#       token           STARTTLS control token.
#       featuresList    XMPP features list from server.
#
# Result:
#       Empty string.
#
# Side effects:
#       Either a STARTTLS request is sent to server or negotiation is
#       finished with error.

proc ::xmpp::starttls::Continue {token featuresList} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

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

# ::xmpp::starttls::Parse --
#
#       Parse XML elemens in urn:ietf:params:xml:ns:xmpp-tls namespace. They
#       indicate the result of negotiation procedure (success or failure).
#
# Arguments:
#       token           STARTTLS control token.
#       xmlElement      Top-level XML stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A corresponding procedure is called in cases of successful or failed
#       STARTTLS negotiation.

proc ::xmpp::starttls::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

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

# ::xmpp::starttls::Proceed --
#
#       A helper procedure which is called if STARTTLS negotiations succeeded.
#       It switches transport to tls and reopens XMPP stream.
#
# Arguments:
#       token           STARTTLS control token.
#
# Result:
#       Empty string.
#
# Side effects:
#       In case of success XMPP channel becomes encrypted, XMPP stream is
#       reopened.

proc ::xmpp::starttls::Proceed {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    if {[catch {eval [list ::xmpp::SwitchTransport $xlib tls] \
                           $state(tlsArgs)} msg]} {
        set err [::xmpp::stanzaerror::error modify undefined-condition \
                                            -text $msg]
        Finish $token error $err
        return
    }

    set state(reopenStream) \
        [::xmpp::ReopenStream $xlib \
                              -command [namespace code [list Reopened $token]]]
    return
}

# ::xmpp::starttls::Reopened --
#
#       A callback which is invoked when the XMPP server responds to stream
#       reopening. It finishes STARTTLS procedure with error or success.
#
# Arguments:
#       token           STARTTLS control token.
#       status          "ok", "error", "abort", or "timeout".
#       sessionid       Stream session ID in case of success, or error message
#                       otherwise.
#
# Result:
#       Empty string.
#
# Side effects:
#       STARTTLS negotiation is finished.

proc ::xmpp::starttls::Reopened {token status sessionid} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    unset state(reopenStream)

    ::xmpp::Debug $xlib 2 "$token $status $sessionid"

    if {[string equal $status ok]} {
        Finish $token ok $sessionid
    } else {
        Finish $token $status [::xmpp::xml::create error -cdata $sessionid]
    }
}

# ::xmpp::starttls::Failure --
#
#       A helper procedure which is called if STARTTLS negotiations failed. It
#       finishes STARTTLS procedure with error.
#
# Arguments:
#       token           STARTTLS control token.
#       xmlElements     Subelements of <failure/> element which include error.
#
# Result:
#       Empty string.
#
# Side effects:
#       STARTTLS negotiation is finished with error.

proc ::xmpp::starttls::Failure {token xmlElements} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

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

# ::xmpp::starttls::Finish --
#
#       A hepler procedure which finishes negotiation process and destroys
#       STARTTLS control token (or returns to [starttls]).
#
# Arguments:
#       token           STARTTLS control token.
#       status          Status of the negotiations ("ok" means success).
#       xmlData         Either a new stream session ID if status is ok or
#                       error stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       In asynchronous mode a control token is destroyed and a callback is
#       called. In synchronous mode vwait in [starttls] is triggered.

proc ::xmpp::starttls::Finish {token status xmlData} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    ::xmpp::Debug $xlib 2 "$token $status"

    ::xmpp::UnregisterElement $xlib * urn:ietf:params:xml:ns:xmpp-tls

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    if {[string equal $status ok]} {
        ::xmpp::CallBack $xlib status [::msgcat::mc "STARTTLS successful"]
    } else {
        ::xmpp::CallBack $xlib status [::msgcat::mc "STARTTLS failed"]
    }

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $xmlData]
    } else {
        # Synchronous mode
        # Trigger vwait in [starttls]
        set state(status) [list $status $xmlData]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
