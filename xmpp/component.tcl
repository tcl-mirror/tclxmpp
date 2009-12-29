# component.tcl --
#
#      This file is part of the XMPP library. It provides support for the
#      Jabber Component Protocol (XEP-0114).
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require sha1
package require xmpp

package provide xmpp::component 0.1

namespace eval ::xmpp::component {
    namespace export auth abort
}

# ::xmpp::component::auth --
#
#       Authenticate an existing XMPP stream using Jabber Component Protocol
#       described in XEP-0114.
#
# Arguments:
#       xlib                    XMPP token. It must be connected and XMPP
#                               stream with XMLNS jabber:component:accept must
#                               be started.
#       -sessionid  sessionid   Stream session ID (as returned by server in
#                               stream header.
#       -secret     secret      Shared secret to use in authentication.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for authentication
#                               queries.
#       -command    callback    (optional) If present, it turns on asynchronous
#                               mode. After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and either IQ result or error.
#
# Result:
#       In asynchronous mode a control token is returned (it allows to abort
#       authentication process). In synchronous mode either IQ result is
#       returned (if authentication succeded) or IQ error (with return code
#       error in case of error, or break in case of abortion).
#
# Side effects:
#       A variable in ::xmpp::component namespace is created and auth state is
#       stored in it in asunchronous mode. In synchronous mode the Tcl event
#       loop is entered and processing until return.

proc ::xmpp::component::auth {xlib args} {
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
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -sessionid -
            -secret    -
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

    foreach key {-sessionid
                 -secret} {
        if {![info exists state($key)]} {
            unset state
            return -code error [::msgcat::mc "Missing option \"%s\"" $key]
        }
    }

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortAuth $token timeout \
                                    [::msgcat::mc "Component handshake\
                                                   timed out"]]]]
    }

    # handshake element indicates success, error indicates failure
    ::xmpp::RegisterElement $xlib handshake * \
                            [namespace code [list Parse $token]]
    ::xmpp::RegisterElement $xlib error http://etherx.jabber.org/streams \
                            [namespace code [list Parse $token]]

    set secret [encoding convertto utf-8 $state(-sessionid)]
    append secret [encoding convertto utf-8 $state(-secret)]
    set digest [sha1::sha1 $secret]
    set data [::xmpp::xml::create handshake -cdata $digest]

    ::xmpp::Debug $xlib 2 "$token digest = $digest"

    ::xmpp::CallBack $xlib status \
                     [::msgcat::mc "Waiting for component handshake result"]

    ::xmpp::outXML $xlib $data

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

# ::xmpp::component::abort --
#
#       Abort an existion authentication procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::component::auth procedure.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::component::abort {token} {
    AbortAuth $token abort [::msgcat::mc "Component handshake aborted"]
}

# ::xmpp::component::AbortAuth --
#
#       Abort an existion authentication procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::component::auth procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::component::AbortAuth {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    if {[info exists $xlib]} {
        Finish $token $status $msg
    }
    return
}

# ::xmpp::component::Parse --
#
#       A helper procedure which parses server answer on a handshake stanza
#       and finishes authentication process.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::component::auth procedure.
#       xmlElement      XML element to parse.
#
# Result:
#       Empty string.
#
# Side effects:
#       If an answer to handshake is received then authentication is finished.

proc ::xmpp::component::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $xmlElement"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        handshake {
            Finish $token ok {}
        }
        error {
            Finish $token error [::xmpp::streamerror::message $xmlElement]
        }
    }
    return
}

# ::xmpp::component::Finish --
#
#       A hepler procedure which finishes authentication.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::component::auth procedure.
#       status          Status of the authentication (ok means success).
#       msg             Either a result (usually empty) if status is ok or
#                       error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In asynchronous mode a control token is destroyed and a callback is
#       called. In synchronous mode vwait in ::xmpp::component::auth is
#       triggered.

proc ::xmpp::component::Finish {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    ::xmpp::Debug $xlib 2 "$token $status"

    if {[string equal $status ok]} {
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Component handshake succeeded"]
    } else {
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Component handshake failed"]
    }

    # Unregister elements after handshake
    ::xmpp::UnregisterElement $xlib handshake *
    ::xmpp::UnregisterElement $xlib error http://etherx.jabber.org/streams

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $msg]
    } else {
        # Synchronous mode
        # Trigger vwait in [auth]
        set state(status) [list $status $msg]
    }
}

# vim:ts=8:sw=4:sts=4:et
