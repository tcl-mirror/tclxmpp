# auth.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       non-SASL authentication layer (XEP-0078).
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require sha1
package require xmpp

package provide xmpp::auth 0.1

namespace eval ::xmpp::auth {
    namespace export auth abort
}

# ::xmpp::auth::auth --
#
#       Authenticate an existing XMPP stream using non-SASL method described
#       in XEP-0078.
#
# Arguments:
#       xlib                    XMPP token. It must be connected and XMPP
#                               stream must be opened.
#       -sessionid  sessionid   Stream session ID (as returned by server in
#                               stream header.
#       -username   username    Username to authenticate.
#       -password   password    Password to use in authentication.
#       -resource   resource    XMPP resource to bind to the stream after
#                               successful authentication.
#       -digest     digest      (optional, defaults to "yes") Boolean value
#                               which specifies if a digest authentication
#                               method should be used. A special value "auto"
#                               allows to select digest authentication if it's
#                               available and fallback to plaintext if the
#                               digest method isn't provided by server.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for authentication
#                               queries.
#       -command    callback    (optional) If present, it turns on asynchronous
#                               mode. After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and either authenticated JID if
#                               status is "ok", or error stanza otherwise.
#
# Result:
#       In asynchronous mode a control token is returned (it allows to abort
#       authentication process). In synchronous mode either authenticated JID
#       is returned (if authentication succeded) or IQ error (with return code
#       error in case of error, or break in case of abortion).
#
# Side effects:
#       A variable in ::xmpp::auth namespace is created and auth state is
#       stored in it in asunchronous mode. In synchronous mode the Tcl event
#       loop is entered and processing until return.

proc ::xmpp::auth::auth {xlib args} {
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
    set state(-digest)  1
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -sessionid -
            -username  -
            -password  -
            -resource  -
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            -digest {
                if {[string is true -strict $val]} {
                    set state(-digest) 1
                } elseif {[string is false -strict $val]} {
                    set state(-digest) 0
                } elseif {[string equal $val auto]} {
                    set state(-digest) 0.5
                } else {
                    unset state
                    return -code error \
                           -errorinfo [::msgcat::mc \
                                           "Illegal value \"%s\" for\
                                            option \"%s\"" $val $key]
                }
            }
            default {
                unset state
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    foreach key {-sessionid
                 -username
                 -password
                 -resource} {
        if {![info exists state($key)]} {
            unset state
            return -code error \
                   -errorinfo [::msgcat::mc "Missing option \"%s\"" $key]
        }
    }

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortAuth $token timeout \
                                    [::msgcat::mc "Non-SASL authentication\
                                                   timed out"]]]]
    }

    ::xmpp::TraceStreamFeatures $xlib [namespace code [list Continue $token]]

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

# ::xmpp::auth::abort --
#
#       Abort an existion authentication procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::auth::auth procedure.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::auth::abort {token} {
    AbortAuth $token abort [::msgcat::mc "Non-SASL authentication aborted"]]
}

# ::xmpp::auth::AbortAuth --
#
#       Abort an existion authentication procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::auth::auth procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::auth::AbortAuth {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::RemoveTraceStreamFeatures $xlib \
                                      [namespace code [list Continue $token]]

    set error [::xmpp::xml::create error -cdata $msg]

    if {[info exists state(id)]} {
        ::xmpp::abortIQ $xlib $state(id) $status $error
    } else {
        Finish $token $status $error
    }
    return
}

# ::xmpp::auth::Continue --
#
#       A hepler procedure which checks if there is an auth feature in a
#       features list provided by server and continues or finishes
#       authentication.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::auth::auth procedure.
#       featuresList    XMPP features list from server.
#
# Result:
#       Empty string.
#
# Side effects:
#       Either an auth form query is sent to server or authentication is
#       finished with error.

proc ::xmpp::auth::Continue {token featuresList} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $featuresList"

    if {![FindFeature $featuresList]} {
        Finish $token error \
               [::xmpp::stanzaerror::error modify not-acceptable \
                        -text [::msgcat::mc "Server hasn't provided non-SASL\
                                             authentication feature"]]
        return
    }

    set data [::xmpp::xml::create query \
                    -xmlns jabber:iq:auth \
                    -subelement [::xmpp::xml::create username \
                                       -cdata $state(-username)]]

    ::xmpp::CallBack $xlib \
                     status [::msgcat::mc "Waiting for non-SASL \
                                           authentication fields"]

    set state(id) \
        [::xmpp::sendIQ $xlib get \
                        -query $data \
                        -command [namespace code [list Continue2 $token]]]
    return
}

# ::xmpp::auth::FindFeature --
#
#       A helper procedure which searches for iq-auth feature in features
#       list.
#
# Arguments:
#       featuresList    List of XMPP stream features as provided by server.
#
# Result:
#       1 if iq-auth featue is found, 0 otherwise.
#
# Side effects:
#       None.

proc ::xmpp::auth::FindFeature {featuresList} {
    foreach feature $featuresList {
        ::xmpp::xml::split $feature tag xmlns attrs cdata subels

        switch -- $tag/$xmlns {
            auth/http://jabber.org/features/iq-auth {
                return 1
            }
        }
    }
    return 0
}

# ::xmpp::auth::Continue2 --
#
#       A hepler procedure which receives authentication form, checks
#       for allowed authentication methods and continues or finishes
#       authentication.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::auth::auth procedure.
#       status          Status of the previous IQ request (ok means success).
#       xmldata         Either an auth form (if status is ok) or error stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       Either a filled auth form is sent to server or authentication is
#       finished with error.

proc ::xmpp::auth::Continue2 {token status xmldata} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $status"

    if {![string equal $status ok]} {
        Finish $token $status $xmldata
        return
    }

    ::xmpp::xml::split $xmldata tag xmlns attrs cdata subels

    set authtype none
    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -glob -- $stag/$authtype {
            password/none -
            password/forbidden {
                if {$state(-digest) < 1} {
                    set authtype plain
                } else {
                    set authtype forbidden
                }
            }
            digest/plain {
                if {$state(-digest) > 0} {
                    set authtype digest
                }
            }
            digest/* {
                if {$state(-digest) > 0} {
                    set authtype digest
                } else {
                    set authtype forbidden
                }
            }
        }
    }

    switch -glob -- $authtype/$state(-digest) {
        plain/* {
            set data [::xmpp::xml::create query \
                          -xmlns jabber:iq:auth \
                          -subelements [list [::xmpp::xml::create username \
                                                  -cdata $state(-username)] \
                                             [::xmpp::xml::create password \
                                                  -cdata $state(-password)] \
                                             [::xmpp::xml::create resource \
                                                  -cdata $state(-resource)]]]
        }
        digest/* {
            set secret [encoding convertto utf-8 $state(-sessionid)]
            append secret [encoding convertto utf-8 $state(-password)]
            set digest [sha1::sha1 $secret]
            set data [::xmpp::xml::create query \
                          -xmlns jabber:iq:auth \
                          -subelements [list [::xmpp::xml::create username \
                                                  -cdata $state(-username)] \
                                             [::xmpp::xml::create digest \
                                                  -cdata $digest] \
                                             [::xmpp::xml::create resource \
                                                  -cdata $state(-resource)]]]
        }
        forbidden/1 {
            Finish $token error \
                   [::xmpp::stanzaerror::error modify not-acceptable -text \
                            [::msgcat::mc "Server doesn't support digest\
                                           non-SASL authentication"]]
            return
        }
        forbidden/0 {
            Finish $token error \
                   [::xmpp::stanzaerror::error modify not-acceptable -text \
                            [::msgcat::mc "Server doesn't support plaintext\
                                           non-SASL authentication"]]
            return
        }
        default {
            Finish $token error \
                   [::xmpp::stanzaerror::error modify not-acceptable -text \
                            [::msgcat::mc "Server doesn't support plaintext or\
                                           digest non-SASL authentication"]]
            return
        }
    }

    ::xmpp::CallBack $xlib status \
                     [::msgcat::mc "Waiting for non-SASL authentication\
                                    results"]

    set state(id) \
        [::xmpp::sendIQ $xlib set \
                        -query $data \
                        -command [namespace code [list Finish $token]]]
    return
}

# ::xmpp::auth::Finish --
#
#       A hepler procedure which receives an answer for the authentication
#       form request and finishes authentication.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::auth::auth procedure.
#       status          Status of the previous IQ request (ok means success).
#       xmlData         Either a result (usually empty) if status is ok or
#                       error stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       In asynchronous mode a control token is destroyed and a callback is
#       called. In synchronous mode vwait in ::xmpp::auth::auth is triggered.

proc ::xmpp::auth::Finish {token status xmlData} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    set jid [::xmpp::jid::jid $state(-username) \
                              [::xmpp::Set $xlib server] \
                              $state(-resource)]

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    ::xmpp::Debug $xlib 2 "$token $status $xmlData"

    if {[string equal $status ok]} {
        set msg $jid
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Non-SASL authentication succeeded"]
    } else {
        set msg [::xmpp::stanzaerror::message $xmlData]
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Non-SASL authentication failed"]
    }

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $msg]
    } else {
        # Synchronous mode
        # Trigger vwait in [auth]
        set state(status) [list $status $msg]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
