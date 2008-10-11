# compress.tcl --
#
#       This file is part of the XMPP library. It provides support for
#       Stream Compression (XEP-0138).
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::stanzaerror 0.1
package require xmpp::transport::zlib 0.1

package provide xmpp::compress 0.1

namespace eval ::xmpp::compress {
    variable SupportedMethods {zlib}

    foreach {lcode type cond description} [list \
        409 modify setup-failed       [::msgcat::mc "Compression setup\
                                                     failed"] \
        409 modify unsupported-method [::msgcat::mc "Unsupported compression\
                                                     method"]] \
    {
        ::xmpp::stanzaerror::registerError $lcode $type $cond $description
    }
}

# ::xmpp::compress::compress --
#
#       Negotiate XMPP stream compression using method from XEP-0138 and switch
#       to a compressed stream.
#
# Arguments:
#       xlib                    XMPP token. It must be connected and XMPP
#                               stream must be opened.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for compression
#                               negotiation.
#       -command    callback    (optional) If present, it turns on asynchronous
#                               mode. After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and either new stream session ID if
#                               status is "ok", or error stanza otherwise.
#       -level level            Compression level.
#
# Result:
#       In asynchronous mode a control token is returned (it allows to abort
#       compression process). In synchronous mode either new stream session ID
#       is returned (if compression succeded) or IQ error (with return code
#       error in case of error, or break in case of abortion).
#
# Side effects:
#       A variable in ::xmpp::compress namespace is created and compression
#       state is stored in it in asynchronous mode. In synchronous mode the
#       Tcl event loop is entered and processing until return.

proc ::xmpp::compress::compress {xlib args} {
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
    set state(zlibArgs) {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -level {
                lappend state(zlibArgs) $key $val
            }
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            default {
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::RegisterElement $xlib * http://jabber.org/protocol/compress \
                            [namespace code [list Parse $token]]

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortCompression $token timeout \
                                    [::msgcat::mc "Compression timed out"]]]]
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

# ::xmpp::compress::abort --
#
#       Abort an existing compression procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Compression control token which is returned by
#                       ::xmpp::compress::compress procedure.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::compress::abort {token} {
    AbortCompression $token abort [::msgcat::mc "Compression aborted"]
}

# ::xmpp::compress::AbortCompression --
#
#       Abort an existing compression procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Compression control token which is returned by
#                       ::xmpp::compress::compress procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::compress::AbortCompression {token status msg} {
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

# ::xmpp::compress::Parse --
#
#       Parse XML elemens in http://jabber.org/protocol/compress namespace.
#       They indicate the result of negotiation procedure (success or failure).
#
# Arguments:
#       token           Compression control token.
#       xmlElement      Top-level XML stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A corresponding procedure is called in cases of successful or failed
#       compression negotiation.

proc ::xmpp::compress::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        compressed {
            Compressed $token
        }
        failure {
            Failure $token $subels
        }
    }
    return
}

# ::xmpp::compress::Continue --
#
#       A helper procedure which checks if there is a compression feature and
#       a supported method in a features list provided by server and continues
#       or finishes compression negotiation.
#
# Arguments:
#       token           Compression control token.
#       featuresList    XMPP features list from server.
#
# Result:
#       Empty string.
#
# Side effects:
#       Either a compression request is sent to server or negotiation is
#       finished with error.

proc ::xmpp::compress::Continue {token featuresList} {
    variable SupportedMethods
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $featuresList"

    if {[catch {FindMethods $featuresList} methods]} {
        Finish $token error \
               [::xmpp::stanzaerror::error modify not-acceptable -text \
                        [::msgcat::mc "Server hasn't provided\
                                       compress feature"]]
        return
    }

    ::xmpp::Debug $xlib 2 "$token methods: $methods"

    foreach m $SupportedMethods {
        if {[lsearch -exact $methods $m] >= 0} {
            set method $m
            break
        }
        if {![info exists method]} {
            Finish $token error \
                   [::xmpp::stanzaerror::error modify not-acceptable \
                         -text [::msgcat::mc \
                                    "Server hasn't provided supported\
                                     compress method"]]
            return
        }
    }

    set state(method) $method

    set data [::xmpp::xml::create compress \
                  -xmlns http://jabber.org/protocol/compress \
                  -subelement [::xmpp::xml::create method -cdata $method]]

    ::xmpp::outXML $xlib $data
    return
}

# ::xmpp::compress::FindMethods --
#
#       A helper procedure which searches for compress feature and extracts
#       compression methods supported by server in features list.
#
# Arguments:
#       featuresList    List of XMPP stream features as provided by server.
#
# Result:
#       List of supported compression methods if the featue is found, error
#       otherwise.
#
# Side effects:
#       None.

proc ::xmpp::compress::FindMethods {featuresList} {
    set compressFeature 0
    set methods {}

    foreach feature $featuresList {
        ::xmpp::xml::split $feature tag xmlns attrs cdata subels

        if {[string equal $xmlns http://jabber.org/features/compress] && \
                [string equal $tag compression]} {
            set compressFeature 1
            set methods {}
            foreach subel $subels {
                ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
                if {[string equal $stag method]} {
                    lappend methods $scdata
                }
            }
        }
    }

    if {$compressFeature} {
        return $methods
    } else {
        return -code error
    }
}

# ::xmpp::compress::Failure --
#
#       A helper procedure which is called if compression negotiations failed.
#       It finishes compression procedure with error.
#
# Arguments:
#       token           Compression control token.
#       xmlElements     Subelements of <failure/> element which include error.
#
# Result:
#       Empty string.
#
# Side effects:
#       Compression negotiation is finished with error.

proc ::xmpp::compress::Failure {token xmlElements} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    set error [lindex $xmlElements 0]
    if {[string equal $error ""]} {
        set err [::xmpp::stanzaerror::error modify undefined-condition \
                     -text [::msgcat::mc "Compression negotiation failed"]]
    } else {
        ::xmpp::xml::split $error tag xmlns attrs cdata subels
        set err [::xmpp::stanzaerror::error modify $tag]
    }

    Finish $token error $err
}

# ::xmpp::compress::Compressed --
#
#       A helper procedure which is called if compression negotiations
#       succeeded. It switches transport to zlib and reopens XMPP stream.
#
# Arguments:
#       token           Compression control token.
#
# Result:
#       Empty string.
#
# Side effects:
#       XMPP channel becomes compressed, XMPP stream is reopened.

proc ::xmpp::compress::Compressed {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    eval [list ::xmpp::SwitchTransport $xlib $state(method)] $state(zlibArgs)

    set state(reopenStream) \
        [::xmpp::ReopenStream $xlib \
                              -command [namespace code [list Reopened $token]]]
    return
}

# ::xmpp::compress::Reopened --
#
#       A callback which is invoked when the XMPP server responds to stream
#       reopening. It finishes compression procedure with error or success.
#
# Arguments:
#       token           Compression control token.
#       status          "ok", "error", "abort", or "timeout".
#       sessionid       Stream session ID in case of success, or error message
#                       otherwise.
#
# Result:
#       Empty string.
#
# Side effects:
#       Compression negotiation is finished.

proc ::xmpp::compress::Reopened {token status sessionid} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    unset state(reopenStream)

    ::xmpp::Debug $xlib 2 "$token $status $sessionid"

    if {[string equal $status $ok]} {
        Finish $token ok $sessionid
    } else {
        Finish $token $status [::xmpp::xml::create error -cdata $sessionid]
    }
}

# ::xmpp::compress::Finish --
#
#       A hepler procedure which finishes negotiation process and destroys
#       compression control token (or returns to [compress]).
#
# Arguments:
#       token           Compression control token.
#       status          Status of the negotiations ("ok" means success).
#       xmlData         Either a result (usually empty) if status is ok or
#                       error stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       In asynchronous mode a control token is destroyed and a callback is
#       called. In synchronous mode vwait in [compress] is triggered.

proc ::xmpp::compress::Finish {token status xmlData} {
    variable $token
    upvar 0 $token state

    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    ::xmpp::UnregisterElement $xlib * http://jabber.org/protocol/compress

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    ::xmpp::Debug $xlib 2 "$token $status"

    if {[string equal $status ok]} {
        set msg $xmlData
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Compression negotiation successful"]
    } else {
        set msg [::xmpp::stanzaerror::message $xmlData]
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Compression negotiation failed"]
    }

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $msg]
    } else {
        # Synchronous mode
        # Trigger vwait in [compress]
        set state(status) [list $status $msg]
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
